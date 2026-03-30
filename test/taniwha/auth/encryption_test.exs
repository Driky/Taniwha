defmodule Taniwha.Auth.EncryptionTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Taniwha.Auth.Encryption

  @key "a_test_secret_key_base_of_sufficient_length_for_testing_purposes"

  # ── Batch A1: round-trip ──────────────────────────────────────────────────

  describe "encrypt/2 + decrypt/2 round-trip" do
    test "decrypting an encrypted value returns the original plaintext" do
      plaintext = "hello, world!"
      encrypted = Encryption.encrypt(plaintext, @key)
      assert {:ok, ^plaintext} = Encryption.decrypt(encrypted, @key)
    end

    test "round-trip works with a UTF-8 JSON payload" do
      plaintext = ~s({"version":1,"users":[{"username":"héllo","role":"admin"}]})
      encrypted = Encryption.encrypt(plaintext, @key)
      assert {:ok, ^plaintext} = Encryption.decrypt(encrypted, @key)
    end
  end

  # ── Batch A2: randomised IVs ──────────────────────────────────────────────

  describe "IV randomisation" do
    test "encrypting the same plaintext twice produces different ciphertexts" do
      plaintext = "same content"
      c1 = Encryption.encrypt(plaintext, @key)
      c2 = Encryption.encrypt(plaintext, @key)
      refute c1 == c2
    end
  end

  # ── Batch A3: tamper resistance ───────────────────────────────────────────

  describe "decrypt/2 tamper resistance" do
    test "wrong key returns {:error, :decryption_failed}" do
      encrypted = Encryption.encrypt("secret", @key)
      assert {:error, :decryption_failed} = Encryption.decrypt(encrypted, "wrong_key")
    end

    test "mutating a byte in the ciphertext body returns {:error, :decryption_failed}" do
      encrypted = Encryption.encrypt("secret data that is long enough", @key)
      # Ciphertext body starts at byte 28 (12 IV + 16 tag)
      mutated = flip_byte(encrypted, 28)
      assert {:error, :decryption_failed} = Encryption.decrypt(mutated, @key)
    end

    test "mutating the GCM tag returns {:error, :decryption_failed}" do
      encrypted = Encryption.encrypt("secret data", @key)
      # GCM tag starts at byte 12 (after the 12-byte IV)
      mutated = flip_byte(encrypted, 12)
      assert {:error, :decryption_failed} = Encryption.decrypt(mutated, @key)
    end

    test "binary too short to contain header returns {:error, :decryption_failed}" do
      assert {:error, :decryption_failed} = Encryption.decrypt(<<1, 2, 3>>, @key)
    end

    test "empty binary returns {:error, :decryption_failed}" do
      assert {:error, :decryption_failed} = Encryption.decrypt(<<>>, @key)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp flip_byte(binary, position) do
    <<head::binary-size(position), byte, tail::binary>> = binary
    <<head::binary, bxor(byte, 0xFF), tail::binary>>
  end
end
