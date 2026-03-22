defmodule Taniwha.Auth do
  @moduledoc """
  JWT authentication via Guardian.

  Issues and verifies JWT tokens for the Taniwha API.
  Tokens are issued in exchange for a valid API key and verified on
  every authenticated request (REST plug) and WebSocket connection.
  """

  use Guardian, otp_app: :taniwha

  @api_subject "api_user"

  @doc """
  Returns the signing secret derived from the endpoint's `secret_key_base`.

  Used by Guardian via the `secret_key: {Taniwha.Auth, :fetch_secret, []}` config
  so the secret is read at runtime rather than baked into compiled code.
  """
  @spec fetch_secret() :: binary()
  def fetch_secret do
    Application.fetch_env!(:taniwha, TaniwhaWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end

  @doc "Guardian callback: encodes the resource as the token subject."
  @spec subject_for_token(resource :: String.t(), claims :: map()) ::
          {:ok, String.t()} | {:error, term()}
  @impl Guardian
  def subject_for_token(resource, _claims), do: {:ok, resource}

  @doc "Guardian callback: decodes the resource from token claims."
  @spec resource_from_claims(claims :: map()) :: {:ok, String.t()} | {:error, term()}
  @impl Guardian
  def resource_from_claims(%{"sub" => sub}), do: {:ok, sub}
  def resource_from_claims(_), do: {:error, :missing_claims}

  @doc """
  Issues a JWT for the given API key.

  Returns `{:ok, token}` if the key matches the configured `:api_key`,
  or `{:error, :invalid_api_key}` otherwise. Uses a constant-time
  comparison to prevent timing attacks.
  """
  @spec issue_token(api_key :: term()) :: {:ok, String.t()} | {:error, term()}
  def issue_token(api_key) do
    stored_key = Application.get_env(:taniwha, :api_key)

    if is_binary(stored_key) and is_binary(api_key) and
         Plug.Crypto.secure_compare(api_key, stored_key) do
      case encode_and_sign(@api_subject, %{}, ttl: {1, :hour}) do
        {:ok, token, _claims} -> {:ok, token}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_api_key}
    end
  end

  @doc """
  Verifies a JWT and returns its subject on success.

  Returns `{:ok, subject}` or `{:error, reason}` (e.g. `:token_expired`,
  `:invalid_token`).
  """
  @spec verify_token(token :: term()) :: {:ok, String.t()} | {:error, term()}
  def verify_token(token) do
    case decode_and_verify(token) do
      {:ok, claims} -> {:ok, claims["sub"]}
      {:error, reason} -> {:error, reason}
    end
  end
end
