defmodule TaniwhaWeb.UserAuth do
  @moduledoc """
  LiveView `on_mount` callbacks for session-based browser authentication.

  Two mount variants are provided:

  - `:require_authenticated_user` — reads `"user_id"` from the session,
    assigns `:current_user` to the socket, or halts with a redirect to
    `/login` if the user is not authenticated.

  - `:redirect_if_authenticated` — redirects already-authenticated users
    away from `/login` and `/setup` to the dashboard. Continues unchanged
    when no valid session is found.

  ## Usage

      # In router.ex
      live_session :authenticated,
        on_mount: [{TaniwhaWeb.UserAuth, :require_authenticated_user}] do
        live "/", DashboardLive, :index
      end

      live_session :unauthenticated,
        on_mount: [{TaniwhaWeb.UserAuth, :redirect_if_authenticated}] do
        live "/login", LoginLive, :index
      end
  """

  use Phoenix.VerifiedRoutes,
    endpoint: TaniwhaWeb.Endpoint,
    router: TaniwhaWeb.Router,
    statics: TaniwhaWeb.static_paths()

  import Phoenix.LiveView, only: [redirect: 2]
  import Phoenix.Component, only: [assign: 3]

  alias Taniwha.Auth.CredentialStore

  @doc """
  Requires an authenticated user in the session.

  Assigns `:current_user` to the socket and continues, or redirects to
  `/login` if no valid user is found.
  """
  @spec on_mount(
          :require_authenticated_user | :redirect_if_authenticated,
          map(),
          map(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_authenticated_user, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} ->
        {:cont, assign(socket, :current_user, user)}

      :error ->
        {:halt, redirect(socket, to: ~p"/login")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, _user} ->
        {:halt, redirect(socket, to: ~p"/")}

      :error ->
        {:cont, socket}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  @spec authenticate_from_session(map()) :: {:ok, map()} | :error
  defp authenticate_from_session(%{"user_id" => user_id}) when is_binary(user_id) do
    case CredentialStore.get_user(user_id) do
      {:ok, user} -> {:ok, user}
      {:error, :not_found} -> :error
    end
  end

  defp authenticate_from_session(_session), do: :error
end
