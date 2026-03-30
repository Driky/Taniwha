defmodule TaniwhaWeb.LoginLive do
  @moduledoc """
  LiveView for the login page (`/login`).

  Validates credentials client-side (via LiveView events) and triggers a
  standard HTTP form POST to `POST /session` on success using
  `phx-trigger-action`. This allows `SessionController` to write the
  encrypted session cookie over HTTP while LiveView handles validation
  feedback without a page reload.

  Already-authenticated users are redirected to `/` via the
  `TaniwhaWeb.UserAuth.redirect_if_authenticated` `on_mount` callback.
  """

  use TaniwhaWeb, :live_view

  alias Taniwha.Auth.CredentialStore

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:trigger_submit, false)
      |> assign(:error, nil)
      |> assign(:page_title, "Sign in")

    {:ok, socket}
  end

  @impl true
  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    case CredentialStore.authenticate(username, password) do
      {:ok, _user} ->
        {:noreply, assign(socket, :trigger_submit, true)}

      {:error, :invalid_credentials} ->
        {:noreply, assign(socket, :error, "Invalid username or password.")}
    end
  end

  def handle_event("use_passkey", _params, socket) do
    {:noreply, put_flash(socket, :info, "Passkeys are not yet available. Stay tuned!")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen flex items-center justify-content:center"
      style="background: #f9fafb; display: flex; align-items: center; justify-content: center;"
    >
      <div style="width: 380px; background: #fff; border: 1px solid #e5e7eb; border-radius: 16px; box-shadow: 0 4px 24px rgba(0,0,0,0.06); padding: 40px;">
        <%!-- Logo --%>
        <div style="text-align: center; margin-bottom: 6px;">
          <span style="font-size: 16px; font-weight: 800; letter-spacing: -0.03em; color: #111827;">
            Taniwha
          </span>
        </div>
        <%!-- Subtitle --%>
        <p style="font-size: 13px; color: #6b7280; text-align: center; margin: 0 0 24px;">
          Sign in to your account
        </p>

        <%!-- Inline info flash (layout flash is not reachable in LiveView inner renders) --%>
        <p
          :if={@flash["info"]}
          role="status"
          style="font-size: 12px; color: #059669; background: #ecfdf5; border: 1px solid #6ee7b7; border-radius: 8px; padding: 10px 12px; margin-bottom: 16px; text-align: center;"
        >
          {@flash["info"]}
        </p>

        <%!-- Login form — phx-trigger-action submits to POST /session when trigger_submit is true --%>
        <form
          id="login-form"
          action={~p"/session"}
          method="post"
          phx-submit="login"
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <div style="display: flex; flex-direction: column; gap: 16px; margin-bottom: 20px;">
            <%!-- Username --%>
            <div>
              <label
                for="username-input"
                style="display: block; font-size: 11px; color: #374151; font-weight: 500; margin-bottom: 4px;"
              >
                Username
              </label>
              <input
                id="username-input"
                type="text"
                name="username"
                autofocus
                autocomplete="username"
                aria-required="true"
                style="height: 36px; width: 100%; border: 1px solid #d1d5db; border-radius: 8px; padding: 0 12px; font-size: 13px; color: #111827; background: #fff; outline: none; box-sizing: border-box;"
              />
            </div>
            <%!-- Password --%>
            <div>
              <label
                for="password-input"
                style="display: block; font-size: 11px; color: #374151; font-weight: 500; margin-bottom: 4px;"
              >
                Password
              </label>
              <input
                id="password-input"
                type="password"
                name="password"
                autocomplete="current-password"
                aria-required="true"
                aria-describedby={if @error, do: "login-error", else: nil}
                style={"height: 36px; width: 100%; border: 1px solid #{if @error, do: "#ef4444", else: "#d1d5db"}; border-radius: 8px; padding: 0 12px; font-size: 13px; color: #111827; background: #fff; outline: none; box-sizing: border-box;#{if @error, do: " box-shadow: 0 0 0 2px rgba(239,68,68,0.15);", else: ""}"}
              />
              <p
                :if={@error}
                id="login-error"
                role="alert"
                style="font-size: 11px; color: #ef4444; margin-top: 4px;"
              >
                {@error}
              </p>
            </div>
          </div>
          <%!-- Sign in button --%>
          <button
            type="submit"
            style="height: 36px; background: #2563eb; color: #fff; font-size: 13px; font-weight: 500; border-radius: 8px; border: none; width: 100%; cursor: pointer; margin-bottom: 8px;"
          >
            Sign in
          </button>
        </form>

        <%!-- Divider --%>
        <div style="display: flex; align-items: center; gap: 8px; margin: 4px 0;">
          <div style="flex: 1; height: 1px; background: #e5e7eb;"></div>
          <span style="font-size: 11px; color: #9ca3af;">or</span>
          <div style="flex: 1; height: 1px; background: #e5e7eb;"></div>
        </div>

        <%!-- Passkey button --%>
        <button
          type="button"
          phx-click="use_passkey"
          style="height: 36px; background: #fff; color: #374151; font-size: 13px; font-weight: 500; border-radius: 8px; border: 1px solid #d1d5db; width: 100%; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; margin-top: 8px;"
        >
          <svg
            style="width: 14px; height: 14px;"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 11c0 3.517-1.009 6.799-2.753 9.571m-3.44-2.04l.054-.09A13.916 13.916 0 008 11a4 4 0 118 0c0 1.017-.07 2.019-.203 3m-2.118 6.844A21.88 21.88 0 0015.171 17m3.839 1.132c.645-2.266.99-4.659.99-7.132A8 8 0 008 4.07M3 15.364c.64-1.319 1-2.8 1-4.364 0-1.457.39-2.823 1.07-4"
            />
          </svg>
          Use a passkey
        </button>
      </div>
    </div>
    """
  end
end
