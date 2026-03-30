defmodule TaniwhaWeb.SetupLive do
  @moduledoc """
  LiveView for first-run admin account creation (`/setup`).

  If any users already exist, redirects immediately to `/login`.

  A race-condition guard re-checks `has_any_users?/0` on submit to prevent
  two concurrent clients from both creating admin accounts.
  """

  use TaniwhaWeb, :live_view

  alias Taniwha.Auth.CredentialStore

  @impl true
  def mount(_params, _session, socket) do
    if CredentialStore.has_any_users?() do
      {:ok, push_navigate(socket, to: ~p"/login")}
    else
      socket =
        socket
        |> assign(:error, nil)
        |> assign(:password_strength, nil)
        |> assign(:page_title, "Setup")

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    password = Map.get(params, "password", "")
    strength = if String.length(password) >= 8, do: :strong, else: :weak
    {:noreply, assign(socket, :password_strength, strength)}
  end

  def handle_event("create_admin", params, socket) do
    %{
      "username" => username,
      "password" => password,
      "password_confirmation" => password_confirmation
    } = params

    # Race-condition guard
    if CredentialStore.has_any_users?() do
      {:noreply, assign(socket, :error, "Admin account has already been configured.")}
    else
      with :ok <- validate_passwords(password, password_confirmation),
           {:ok, _user} <- CredentialStore.create_user(username, password) do
        {:noreply,
         socket
         |> put_flash(:info, "Admin account created. Please sign in.")
         |> push_navigate(to: ~p"/login")}
      else
        {:error, :too_short} ->
          {:noreply, assign(socket, :error, "Password must be at least 8 characters.")}

        {:error, :password_mismatch} ->
          {:noreply, assign(socket, :error, "Passwords do not match.")}

        {:error, :username_taken} ->
          {:noreply, assign(socket, :error, "Username is already taken.")}

        {:error, :empty_username} ->
          {:noreply, assign(socket, :error, "Username cannot be blank.")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; background: #f9fafb; display: flex; align-items: center; justify-content: center;">
      <div style="width: 380px; background: #fff; border: 1px solid #e5e7eb; border-radius: 16px; box-shadow: 0 4px 24px rgba(0,0,0,0.06); padding: 40px;">
        <%!-- Logo --%>
        <div style="text-align: center; margin-bottom: 6px;">
          <span style="font-size: 16px; font-weight: 800; letter-spacing: -0.03em; color: #111827;">
            Taniwha
          </span>
        </div>
        <%!-- Title --%>
        <p style="font-size: 15px; font-weight: 600; color: #111827; text-align: center; margin: 0 0 4px;">
          Create admin account
        </p>
        <%!-- Subtitle --%>
        <p style="font-size: 13px; color: #6b7280; text-align: center; margin: 0 0 24px;">
          Set up your credentials
        </p>

        <form
          id="setup-form"
          phx-submit="create_admin"
          phx-change="validate"
        >
          <div style="display: flex; flex-direction: column; gap: 16px; margin-bottom: 20px;">
            <%!-- Username --%>
            <div>
              <label
                for="setup-username"
                style="display: block; font-size: 11px; color: #374151; font-weight: 500; margin-bottom: 4px;"
              >
                Username
              </label>
              <input
                id="setup-username"
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
                for="setup-password"
                style="display: block; font-size: 11px; color: #374151; font-weight: 500; margin-bottom: 4px;"
              >
                Password
              </label>
              <input
                id="setup-password"
                type="password"
                name="password"
                autocomplete="new-password"
                aria-required="true"
                style="height: 36px; width: 100%; border: 1px solid #d1d5db; border-radius: 8px; padding: 0 12px; font-size: 13px; color: #111827; background: #fff; outline: none; box-sizing: border-box;"
              />
              <p style="font-size: 10px; color: #9ca3af; margin-top: 4px;">Minimum 8 characters</p>
              <%!-- Strength bar --%>
              <div
                :if={@password_strength != nil}
                class={"h-1 rounded mt-1 #{if @password_strength == :strong, do: "bg-green-500", else: "bg-red-500"}"}
                role="progressbar"
                aria-label="Password strength"
              >
              </div>
            </div>
            <%!-- Confirm password --%>
            <div>
              <label
                for="setup-password-confirm"
                style="display: block; font-size: 11px; color: #374151; font-weight: 500; margin-bottom: 4px;"
              >
                Confirm Password
              </label>
              <input
                id="setup-password-confirm"
                type="password"
                name="password_confirmation"
                autocomplete="new-password"
                aria-required="true"
                style="height: 36px; width: 100%; border: 1px solid #d1d5db; border-radius: 8px; padding: 0 12px; font-size: 13px; color: #111827; background: #fff; outline: none; box-sizing: border-box;"
              />
            </div>
          </div>

          <%!-- Error message --%>
          <p
            :if={@error}
            role="alert"
            style="font-size: 11px; color: #ef4444; margin-bottom: 12px;"
          >
            {@error}
          </p>

          <%!-- Submit button --%>
          <button
            type="submit"
            style="height: 36px; background: #2563eb; color: #fff; font-size: 13px; font-weight: 500; border-radius: 8px; border: none; width: 100%; cursor: pointer;"
          >
            Create account
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  @spec validate_passwords(String.t(), String.t()) ::
          :ok | {:error, :too_short | :password_mismatch}
  defp validate_passwords(password, confirmation) do
    cond do
      String.length(password) < 8 -> {:error, :too_short}
      password != confirmation -> {:error, :password_mismatch}
      true -> :ok
    end
  end
end
