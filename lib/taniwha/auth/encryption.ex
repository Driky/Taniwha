defmodule Taniwha.Auth.Encryption do
  @moduledoc """
  AES-256-GCM authenticated encryption for secrets at rest.

  Uses Erlang's built-in `:crypto` module — no extra dependencies.

  ## Key derivation

  A 32-byte AES-256 key is derived from Phoenix's `secret_key_base` via
  `SHA-256`. Because `secret_key_base` is already a high-entropy random
  value (≥ 64 bytes), a single SHA-256 hash is sufficient — no PBKDF2
  stretching is needed here.

  ## Wire format

      <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>>

  The 12-byte IV is generated fresh on every `encrypt/2` call, so
  encrypting the same plaintext twice always produces different outputs.
  The 16-byte GCM authentication tag ensures any tampering is detected
  during decryption.

  ## Key rotation warning

  The credential file is encrypted with a key derived from
  `SECRET_KEY_BASE`. **If `SECRET_KEY_BASE` is rotated**, the credential
  file becomes permanently unreadable. There is no automatic migration:
  delete `credentials.enc` and re-create all users after rotating the key.
  """

  @iv_size 12
  @tag_size 16
  # Additional authenticated data — empty string is valid for AES-GCM.
  # Bind to a context string in future if needed without changing the wire format.
  @aad ""

  @doc """
  Encrypts `plaintext` using AES-256-GCM.

  A fresh random IV is generated on each call so the same plaintext
  always produces a different ciphertext.

  Returns a binary in the format:
  `<<iv::12-bytes, tag::16-bytes, ciphertext::binary>>`.
  """
  @spec encrypt(plaintext :: String.t(), secret_key_base :: String.t()) :: binary()
  def encrypt(plaintext, secret_key_base)
      when is_binary(plaintext) and is_binary(secret_key_base) do
    key = derive_key(secret_key_base)
    iv = :crypto.strong_rand_bytes(@iv_size)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    <<iv::binary-size(@iv_size), tag::binary-size(@tag_size), ciphertext::binary>>
  end

  @doc """
  Decrypts a binary produced by `encrypt/2`.

  Returns `{:ok, plaintext}` on success, or `{:error, :decryption_failed}` when:

  - The ciphertext was tampered with (GCM tag mismatch)
  - The wrong `secret_key_base` was supplied
  - The binary is too short to contain the header (IV + tag)
  """
  @spec decrypt(ciphertext :: binary(), secret_key_base :: String.t()) ::
          {:ok, String.t()} | {:error, :decryption_failed}
  def decrypt(
        <<iv::binary-size(@iv_size), tag::binary-size(@tag_size), body::binary>>,
        secret_key_base
      )
      when is_binary(secret_key_base) do
    key = derive_key(secret_key_base)

    result =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, body, @aad, tag, false)

    if is_binary(result) do
      {:ok, result}
    else
      {:error, :decryption_failed}
    end
  end

  # Catch-all: binary too short to contain the 12+16 byte header.
  def decrypt(_too_short, _secret_key_base), do: {:error, :decryption_failed}

  # ── Private ────────────────────────────────────────────────────────────────

  @spec derive_key(String.t()) :: binary()
  defp derive_key(secret_key_base) do
    :crypto.hash(:sha256, secret_key_base)
  end
end
