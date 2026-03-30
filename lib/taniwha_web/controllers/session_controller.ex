defmodule TaniwhaWeb.SessionController do
  @moduledoc """
  Handles browser session creation and deletion for cookie-based auth.

  This controller is the HTTP endpoint for the `phx-trigger-action` form in
  `LoginLive`. It re-validates credentials, sets the session (with fixation
  prevention), and redirects accordingly.

  ## Routes

      post "/session", SessionController, :create
      delete "/session", SessionController, :delete
  """

  use TaniwhaWeb, :controller

  alias Taniwha.Auth.CredentialStore

  @doc """
  Authenticates the user and creates a new session on success.

  On success: renews the session (session fixation prevention), stores
  `user_id`, and redirects to `/`.

  On failure: redirects to `/login` with an error flash message.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"username" => username, "password" => password}) do
    case CredentialStore.authenticate(username, password) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session("user_id", user.id)
        |> redirect(to: ~p"/")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid username or password.")
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  Destroys the current session and redirects to `/login`.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/login")
  end
end
