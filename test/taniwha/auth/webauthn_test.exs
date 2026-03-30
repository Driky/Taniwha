defmodule Taniwha.Auth.WebAuthnTest do
  # async: false because Mox stubs are global per test process
  use ExUnit.Case, async: false

  import Mox

  alias Taniwha.Auth.{MockWax, WebAuthn}

  setup :verify_on_exit!

  # ── Batch 2: Challenge generation (pure functions) ────────────────────────

  describe "registration_options/2" do
    test "returns a map with all required browser options" do
      opts = WebAuthn.registration_options("user123", "alice")

      assert is_binary(opts.challenge_raw)
      assert is_binary(opts.challenge)
      assert is_map(opts.rp)
      assert is_map(opts.user)
      assert is_list(opts.pubKeyCredParams)
      assert is_map(opts.authenticatorSelection)
      assert is_integer(opts.timeout)
      assert is_binary(opts.attestation)
    end

    test "challenge_raw is at least 32 bytes" do
      opts = WebAuthn.registration_options("user123", "alice")
      assert byte_size(opts.challenge_raw) >= 32
    end

    test "challenge is Base64URL encoding of challenge_raw" do
      opts = WebAuthn.registration_options("user123", "alice")
      assert Base.url_decode64!(opts.challenge, padding: false) == opts.challenge_raw
    end

    test "rp.name matches configured rp_name" do
      opts = WebAuthn.registration_options("user123", "alice")
      assert opts.rp.name == "Taniwha"
    end

    test "user.name matches provided username" do
      opts = WebAuthn.registration_options("user123", "alice")
      assert opts.user.name == "alice"
    end

    test "pubKeyCredParams includes ES256 and RS256" do
      opts = WebAuthn.registration_options("user123", "alice")
      algs = Enum.map(opts.pubKeyCredParams, & &1.alg)
      assert -7 in algs
      assert -257 in algs
    end

    test "two consecutive calls produce different challenges" do
      opts1 = WebAuthn.registration_options("user123", "alice")
      opts2 = WebAuthn.registration_options("user123", "alice")
      refute opts1.challenge_raw == opts2.challenge_raw
    end
  end

  describe "assertion_options/0" do
    test "returns a map with all required browser options" do
      opts = WebAuthn.assertion_options()

      assert is_binary(opts.challenge_raw)
      assert is_binary(opts.challenge)
      assert is_binary(opts.rpId)
      assert is_binary(opts.userVerification)
      assert is_integer(opts.timeout)
    end

    test "challenge_raw is at least 32 bytes" do
      opts = WebAuthn.assertion_options()
      assert byte_size(opts.challenge_raw) >= 32
    end

    test "challenge is Base64URL encoding of challenge_raw" do
      opts = WebAuthn.assertion_options()
      assert Base.url_decode64!(opts.challenge, padding: false) == opts.challenge_raw
    end

    test "two consecutive calls produce different challenges" do
      opts1 = WebAuthn.assertion_options()
      opts2 = WebAuthn.assertion_options()
      refute opts1.challenge_raw == opts2.challenge_raw
    end

    test "rpId matches configured rp_id" do
      opts = WebAuthn.assertion_options()
      assert opts.rpId == "localhost"
    end
  end

  # ── Batch 3: Validation with Mox ─────────────────────────────────────────

  # Minimal auth_data struct-like maps returned by the mock
  defp mock_auth_data_for_registration(credential_id, cose_key_map, sign_count \\ 0) do
    %{
      sign_count: sign_count,
      attested_credential_data: %{
        credential_id: credential_id,
        credential_public_key: cose_key_map
      }
    }
  end

  defp mock_auth_data_for_assertion(sign_count) do
    %{sign_count: sign_count}
  end

  describe "register_credential/4" do
    test "returns {:ok, passkey_map} on successful registration" do
      cred_id = :crypto.strong_rand_bytes(32)
      cose_key = %{1 => 2, 3 => -7}
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:register, fn _attest_obj, _cdj, _challenge ->
        {:ok, {mock_auth_data_for_registration(cred_id, cose_key), nil}}
      end)

      assert {:ok, passkey} =
               WebAuthn.register_credential(
                 "client_data_json",
                 "attestation_object",
                 challenge_raw,
                 "Device passkey · Jan 01, 2026"
               )

      assert passkey.credential_id == cred_id
      assert passkey.sign_count == 0
      assert passkey.label == "Device passkey · Jan 01, 2026"
      assert is_binary(passkey.cose_key)
      assert is_binary(passkey.created_at)
    end

    test "cose_key is CBOR-encoded binary" do
      cred_id = :crypto.strong_rand_bytes(32)
      cose_key = %{1 => 2, 3 => -7}
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:register, fn _attest_obj, _cdj, _challenge ->
        {:ok, {mock_auth_data_for_registration(cred_id, cose_key), nil}}
      end)

      {:ok, passkey} =
        WebAuthn.register_credential("cdj", "attest", challenge_raw, "label")

      assert {:ok, decoded_map, _} = CBOR.decode(passkey.cose_key)
      assert decoded_map == cose_key
    end

    test "returns {:error, :registration_failed} when wax_ returns error" do
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:register, fn _attest_obj, _cdj, _challenge ->
        {:error, %RuntimeError{message: "invalid attestation"}}
      end)

      assert {:error, :registration_failed} =
               WebAuthn.register_credential("cdj", "attest", challenge_raw, "label")
    end
  end

  describe "verify_assertion/5" do
    defp make_stored_passkey(sign_count) do
      cose_key_binary = CBOR.encode(%{1 => 2, 3 => -7})

      %{
        id: "pk_id_123",
        credential_id: :crypto.strong_rand_bytes(32),
        cose_key: cose_key_binary,
        sign_count: sign_count,
        label: "Device passkey · Jan 01, 2026",
        created_at: "2026-01-01T00:00:00Z"
      }
    end

    test "returns {:ok, new_sign_count} on successful assertion" do
      passkey = make_stored_passkey(5)
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:ok, mock_auth_data_for_assertion(6)}
      end)

      assert {:ok, 6} =
               WebAuthn.verify_assertion("auth_data", "cdj", "sig", challenge_raw, passkey)
    end

    test "returns {:error, :invalid_assertion} when wax_ returns error" do
      passkey = make_stored_passkey(5)
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:error, %RuntimeError{message: "invalid signature"}}
      end)

      assert {:error, :invalid_assertion} =
               WebAuthn.verify_assertion("auth_data", "cdj", "sig", challenge_raw, passkey)
    end

    test "returns {:error, :sign_count_replay} when new count <= stored count" do
      passkey = make_stored_passkey(10)
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:ok, mock_auth_data_for_assertion(9)}
      end)

      assert {:error, :sign_count_replay} =
               WebAuthn.verify_assertion("auth_data", "cdj", "sig", challenge_raw, passkey)
    end

    test "returns {:error, :sign_count_replay} when new count equals stored count (non-zero)" do
      passkey = make_stored_passkey(5)
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:ok, mock_auth_data_for_assertion(5)}
      end)

      assert {:error, :sign_count_replay} =
               WebAuthn.verify_assertion("auth_data", "cdj", "sig", challenge_raw, passkey)
    end

    test "returns {:ok, 0} when both stored and returned sign_count are 0 (exemption)" do
      passkey = make_stored_passkey(0)
      challenge_raw = :crypto.strong_rand_bytes(32)

      MockWax
      |> expect(:authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:ok, mock_auth_data_for_assertion(0)}
      end)

      assert {:ok, 0} =
               WebAuthn.verify_assertion("auth_data", "cdj", "sig", challenge_raw, passkey)
    end
  end
end
