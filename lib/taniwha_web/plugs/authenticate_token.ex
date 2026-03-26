defmodule TaniwhaWeb.Plugs.AuthenticateToken do
  @moduledoc """
  Plug that authenticates requests via a Bearer JWT token.

  Reads the `Authorization` header, extracts the Bearer token,
  verifies it with `Taniwha.Auth.verify_token/1`, and assigns
  `:current_user` on success. Halts with a 401 JSON response on failure.

  A structured `:warning` log is emitted on every authentication failure.
  The log includes the caller's `remote_ip` for security monitoring but
  never logs the token or API key itself.
  """

  @behaviour Plug

  require Logger

  import Plug.Conn

  @unauthorized_body Jason.encode!(%{error: "unauthorized"})

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user_id} <- Taniwha.Auth.verify_token(token) do
      assign(conn, :current_user, user_id)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    Logger.warning("Authentication failed",
      reason: "invalid_token",
      remote_ip: conn.remote_ip |> :inet.ntoa() |> to_string()
    )

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, @unauthorized_body)
    |> halt()
  end
end
