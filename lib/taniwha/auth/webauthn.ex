defmodule Taniwha.Auth.WebAuthn do
  @moduledoc """
  WebAuthn/Passkey support — challenge generation and ceremony validation.

  Challenge generation (`registration_options/2` and `assertion_options/0`) is
  pure: no external dependencies, easy to unit-test. The raw challenge bytes are
  returned under the `:challenge_raw` key and must be stored in the caller's
  state (e.g. LiveView socket assigns) for later use during validation. They are
  single-use: clear them after first use.

  Validation (`register_credential/4` and `verify_assertion/5`) delegates
  cryptographic work to the configured `:wax_module` (defaults to `Wax`).
  In tests this is replaced with `Taniwha.Auth.MockWax` (see `config/test.exs`).

  ## Sign-count replay detection

  After a successful assertion, the authenticator returns a new sign count.
  `verify_assertion/5` enforces that this count is strictly greater than the
  stored count, which detects cloned authenticators. A stored count of 0 AND a
  returned count of 0 is an exemption (WebAuthn spec §6.1) — some platform
  authenticators always report 0 for privacy reasons.
  """

  @type passkey_map() :: %{
          credential_id: binary(),
          cose_key: binary(),
          sign_count: non_neg_integer(),
          label: String.t(),
          created_at: String.t()
        }

  # Wax.Challenge.new/1 has conditional raises for missing :origin/:rp_id. Since
  # both are always set at runtime (dev.exs / test.exs / runtime.exs), these
  # branches are dead code — but Dialyzer cannot see through Application.get_env
  # and marks the callers as no_return. Suppress at the source.
  @dialyzer {:nowarn_function, register_credential: 4, verify_assertion: 5}

  # ── Configuration helpers ─────────────────────────────────────────────────

  defp webauthn_cfg, do: Application.get_env(:taniwha, :webauthn, [])
  defp origin, do: Keyword.get(webauthn_cfg(), :origin, "http://localhost:4000")
  defp rp_id, do: Keyword.get(webauthn_cfg(), :rp_id, "localhost")
  defp rp_name, do: Keyword.get(webauthn_cfg(), :rp_name, "Taniwha")
  defp attestation, do: Keyword.get(webauthn_cfg(), :attestation, "none")
  defp wax_module, do: Application.get_env(:taniwha, :wax_module, Wax)

  # ── Challenge generation (pure) ───────────────────────────────────────────

  @doc """
  Builds the `publicKeyCredentialCreationOptions` map for the browser.

  Returns a map with:
  - `:challenge_raw` — raw binary (store in socket assigns, pass to `register_credential/4`)
  - `:challenge` — Base64URL-encoded challenge (send to browser JS)
  - Standard WebAuthn fields: `:rp`, `:user`, `:pubKeyCredParams`, etc.
  """
  @spec registration_options(user_id :: String.t(), username :: String.t()) :: map()
  def registration_options(user_id, username) do
    challenge_raw = :crypto.strong_rand_bytes(32)

    %{
      challenge_raw: challenge_raw,
      challenge: Base.url_encode64(challenge_raw, padding: false),
      rp: %{id: rp_id(), name: rp_name()},
      user: %{
        id: Base.url_encode64(user_id, padding: false),
        name: username,
        displayName: username
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      authenticatorSelection: %{userVerification: "preferred"},
      timeout: 60_000,
      attestation: attestation()
    }
  end

  @doc """
  Builds the `publicKeyCredentialRequestOptions` map for the browser.

  Returns a map with:
  - `:challenge_raw` — raw binary (store in socket assigns, pass to `verify_assertion/5`)
  - `:challenge` — Base64URL-encoded challenge (send to browser JS)
  - Standard WebAuthn fields: `:rpId`, `:userVerification`, `:timeout`
  """
  @spec assertion_options() :: map()
  def assertion_options do
    challenge_raw = :crypto.strong_rand_bytes(32)

    %{
      challenge_raw: challenge_raw,
      challenge: Base.url_encode64(challenge_raw, padding: false),
      timeout: 60_000,
      rpId: rp_id(),
      userVerification: "preferred"
    }
  end

  # ── Ceremony validation ───────────────────────────────────────────────────

  @doc """
  Validates a WebAuthn registration response and builds a passkey map.

  - `client_data_json` — raw bytes (Base64-decoded before sending from JS hook)
  - `attestation_object` — raw bytes (Base64-decoded before sending from JS hook)
  - `challenge_raw` — the raw binary stored in socket assigns
  - `label` — human-readable label determined by the JS hook

  Returns `{:ok, passkey_map()}` on success.
  Returns `{:error, :registration_failed}` on any validation error.

  The returned passkey map does not include an `:id` field — `CredentialStore.add_passkey/3`
  generates one automatically.
  """
  @spec register_credential(
          client_data_json :: binary(),
          attestation_object :: binary(),
          challenge_raw :: binary(),
          label :: String.t()
        ) :: {:ok, passkey_map()} | {:error, :registration_failed}
  def register_credential(client_data_json, attestation_object, challenge_raw, label) do
    challenge =
      Wax.new_registration_challenge(
        bytes: challenge_raw,
        origin: origin(),
        rp_id: rp_id(),
        attestation: attestation()
      )

    case wax_module().register(attestation_object, client_data_json, challenge) do
      {:ok, {auth_data, _attestation_result}} ->
        cose_key_binary = CBOR.encode(auth_data.attested_credential_data.credential_public_key)

        passkey = %{
          credential_id: auth_data.attested_credential_data.credential_id,
          cose_key: cose_key_binary,
          sign_count: auth_data.sign_count,
          label: label,
          created_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        {:ok, passkey}

      {:error, _reason} ->
        {:error, :registration_failed}
    end
  end

  @doc """
  Validates a WebAuthn authentication assertion and returns the new sign count.

  - `auth_data_bin` — raw bytes from `credential.response.authenticatorData`
  - `client_data_json` — raw bytes from `credential.response.clientDataJSON`
  - `signature` — raw bytes from `credential.response.signature`
  - `challenge_raw` — the raw binary stored in socket assigns (single-use)
  - `stored_passkey` — the passkey map from `CredentialStore.get_passkey_by_credential_id/2`

  Returns `{:ok, new_sign_count}` on success. The caller must persist `new_sign_count`
  via `CredentialStore.update_passkey_sign_count/4`.

  Returns `{:error, :invalid_assertion}` on signature/origin/rp_id failure.
  Returns `{:error, :sign_count_replay}` when replay protection triggers.
  """
  @spec verify_assertion(
          auth_data_bin :: binary(),
          client_data_json :: binary(),
          signature :: binary(),
          challenge_raw :: binary(),
          stored_passkey :: map()
        ) ::
          {:ok, non_neg_integer()}
          | {:error, :invalid_assertion}
          | {:error, :sign_count_replay}
  def verify_assertion(auth_data_bin, client_data_json, signature, challenge_raw, stored_passkey) do
    challenge =
      Wax.new_authentication_challenge(
        bytes: challenge_raw,
        origin: origin(),
        rp_id: rp_id()
      )

    {:ok, cose_key_map, _rest} = CBOR.decode(stored_passkey.cose_key)
    credentials = [{stored_passkey.credential_id, cose_key_map}]

    case wax_module().authenticate(
           stored_passkey.credential_id,
           auth_data_bin,
           signature,
           client_data_json,
           challenge,
           credentials
         ) do
      {:ok, result_auth_data} ->
        new_count = result_auth_data.sign_count
        stored_count = stored_passkey.sign_count

        cond do
          new_count == 0 and stored_count == 0 -> {:ok, 0}
          new_count > stored_count -> {:ok, new_count}
          true -> {:error, :sign_count_replay}
        end

      {:error, _reason} ->
        {:error, :invalid_assertion}
    end
  end
end
