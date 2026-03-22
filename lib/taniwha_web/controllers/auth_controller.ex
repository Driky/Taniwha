defmodule TaniwhaWeb.AuthController do
  @moduledoc "Handles API key exchange for JWT token issuance."

  use TaniwhaWeb, :controller

  @doc "Issues a JWT given a valid API key."
  @spec token(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def token(conn, %{"api_key" => api_key}) do
    case Taniwha.Auth.issue_token(api_key) do
      {:ok, token} -> json(conn, %{token: token})
      {:error, :invalid_api_key} -> conn |> put_status(401) |> json(%{error: "invalid_api_key"})
    end
  end

  def token(conn, _params) do
    conn |> put_status(400) |> json(%{error: "api_key is required"})
  end
end
