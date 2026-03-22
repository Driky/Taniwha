defmodule TaniwhaWeb.API.AuthController do
  @moduledoc """
  Handles API key exchange for JWT token issuance.
  """

  use TaniwhaWeb, :controller

  @doc """
  Issues a JWT given a valid API key.

  Expects a JSON body with an `"api_key"` field. Returns 422 if the field is
  absent, 401 if the key is invalid, or 200 with `{"token": "<jwt>"}` on success.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"api_key" => api_key}) do
    case Taniwha.Auth.issue_token(api_key) do
      {:ok, token} -> json(conn, %{token: token})
      {:error, :invalid_api_key} -> conn |> put_status(401) |> json(%{error: "invalid_api_key"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(422) |> json(%{error: "api_key is required"})
  end
end
