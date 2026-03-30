defmodule TaniwhaWeb.Plugs.AuthenticateSession do
  @moduledoc """
  Plug that authenticates browser requests via session cookie.

  Reads `"user_id"` from the session, looks it up in
  `Taniwha.Auth.CredentialStore`, and assigns `:current_user` on success.
  Halts with a redirect to `/login` on failure.

  Applied only to the `:browser_auth` pipeline (browser routes that require
  authentication). The JWT-based `:api_authenticated` pipeline is unaffected.
  """

  @behaviour Plug

  use Phoenix.VerifiedRoutes,
    endpoint: TaniwhaWeb.Endpoint,
    router: TaniwhaWeb.Router,
    statics: TaniwhaWeb.static_paths()

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with user_id when is_binary(user_id) <- get_session(conn, "user_id"),
         {:ok, user} <- Taniwha.Auth.CredentialStore.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> redirect(to: ~p"/login")
        |> halt()
    end
  end
end
