defmodule TaniwhaWeb.SettingsLive do
  @moduledoc """
  Settings page LiveView.

  Displays connection status, API key (masked by default with reveal/copy
  actions), and system version information.
  """

  use TaniwhaWeb, :live_view

  alias Taniwha.Auth.{CredentialStore, WebAuthn}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:api_key_revealed, false)
     |> assign(:api_key, Application.get_env(:taniwha, :api_key, ""))
     |> assign(:system_info, build_system_info())
     |> assign(:connection_status, check_connection())
     |> assign(:passkeys, socket.assigns.current_user.passkeys)
     |> assign(:passkey_error, nil)
     |> assign(:reg_challenge, nil)}
  end

  @impl true
  def handle_event("reveal_key", _params, socket) do
    {:noreply, assign(socket, :api_key_revealed, !socket.assigns.api_key_revealed)}
  end

  def handle_event("copy_key", _params, socket) do
    {:noreply, push_event(socket, "copy-to-clipboard", %{text: socket.assigns.api_key})}
  end

  def handle_event("add_passkey", _params, socket) do
    user = socket.assigns.current_user
    opts = WebAuthn.registration_options(user.id, user.username)

    socket =
      socket
      |> assign(:reg_challenge, opts.challenge_raw)
      |> assign(:passkey_error, nil)
      |> push_event("start-passkey-registration", Map.delete(opts, :challenge_raw))

    {:noreply, socket}
  end

  def handle_event(
        "passkey_registered",
        %{
          "credential_id" => cred_id_b64,
          "client_data_json" => cdj_b64,
          "attestation_object" => attest_b64,
          "label" => label
        },
        socket
      ) do
    challenge_raw = socket.assigns.reg_challenge

    _cred_id = Base.decode64!(cred_id_b64)
    client_data_json = Base.decode64!(cdj_b64)
    attestation_object = Base.decode64!(attest_b64)

    socket = assign(socket, :reg_challenge, nil)

    case WebAuthn.register_credential(client_data_json, attestation_object, challenge_raw, label) do
      {:ok, passkey} ->
        {:ok, updated_user} = CredentialStore.add_passkey(socket.assigns.current_user.id, passkey)

        {:noreply,
         socket
         |> assign(:passkeys, updated_user.passkeys)
         |> assign(:passkey_error, nil)}

      {:error, :registration_failed} ->
        {:noreply, assign(socket, :passkey_error, "Passkey registration failed. Please try again.")}
    end
  end

  def handle_event("passkey_registration_error", %{"message" => _msg}, socket) do
    {:noreply,
     socket
     |> assign(:passkey_error, "Passkey registration was cancelled or failed. Please try again.")
     |> assign(:reg_challenge, nil)}
  end

  def handle_event("delete_passkey", %{"id" => passkey_id}, socket) do
    user_id = socket.assigns.current_user.id
    :ok = CredentialStore.delete_passkey(user_id, passkey_id)
    {:ok, updated_user} = CredentialStore.get_user(user_id)
    {:noreply, assign(socket, :passkeys, updated_user.passkeys)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Page wrapper with subtle bg --%>
    <div class="min-h-screen" style="background: var(--taniwha-content-bg)">
      <%!-- Topbar --%>
      <div
        class="flex items-center gap-3 px-8 h-12 border-b"
        style="border-color: var(--taniwha-actionbar-border)"
      >
        <.link
          navigate={~p"/"}
          aria-label="Back to dashboard"
          class="flex items-center gap-1.5 text-[12px] text-gray-500 hover:text-gray-700 dark:hover:text-gray-300"
        >
          <.icon name="hero-arrow-left-mini" class="size-4" /> Dashboard
        </.link>
        <span class="text-gray-300 dark:text-gray-600">/</span>
        <span class="text-[12px] font-semibold text-gray-700 dark:text-gray-200">Settings</span>
      </div>

      <%!-- Content --%>
      <div class="px-10 py-8 max-w-2xl">
        <h1 class="text-[18px] font-semibold text-gray-900 dark:text-gray-50 mb-6">Settings</h1>

        <%!-- Connection section --%>
        <div
          class="mb-5 rounded-[10px] border bg-white dark:bg-[#1a1f2e]"
          style="border-color: #e5e7eb; --tw-border-opacity: 1"
        >
          <div class="px-5 py-[14px] border-b" style="border-color: #f3f4f6">
            <h2 class="text-[13px] font-semibold text-gray-900 dark:text-gray-100">Connection</h2>
          </div>
          <div class="px-5 py-4 flex items-center gap-3" role="status" aria-live="polite">
            <span
              :if={@connection_status == :ok}
              class="size-2 rounded-full shrink-0"
              style="background: #22c55e; box-shadow: 0 0 0 3px rgba(34,197,94,0.2)"
              aria-hidden="true"
            />
            <span
              :if={@connection_status != :ok}
              class="size-2 rounded-full shrink-0 bg-red-500"
              aria-hidden="true"
            />
            <span class="text-[12px] text-gray-700 dark:text-gray-300">
              {if @connection_status == :ok, do: "Connected", else: "Not connected"}
            </span>
          </div>
        </div>

        <%!-- API Key section --%>
        <div
          class="mb-5 rounded-[10px] border bg-white dark:bg-[#1a1f2e]"
          style="border-color: #e5e7eb"
        >
          <div class="px-5 py-[14px] border-b" style="border-color: #f3f4f6">
            <h2 class="text-[13px] font-semibold text-gray-900 dark:text-gray-100">API Key</h2>
          </div>
          <div class="px-5 py-4">
            <div class="flex items-center gap-2 max-w-[480px] rounded-[7px] border border-gray-200 dark:border-gray-600 bg-gray-50 dark:bg-gray-900 px-3 py-2">
              <code class="flex-1 text-[11px] font-mono text-gray-700 dark:text-gray-300 break-all">
                {if @api_key_revealed,
                  do: @api_key,
                  else: String.duplicate("•", min(String.length(@api_key), 32))}
              </code>
              <button
                type="button"
                phx-click="reveal_key"
                aria-label={if @api_key_revealed, do: "Hide API key", else: "Reveal API key"}
                aria-pressed={to_string(@api_key_revealed)}
                class="shrink-0 px-3 py-1.5 text-[11px] rounded-[7px] border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer"
              >
                {if @api_key_revealed, do: "Hide", else: "Reveal"}
              </button>
              <button
                type="button"
                phx-click="copy_key"
                aria-label="Copy API key to clipboard"
                class="shrink-0 px-3 py-1.5 text-[11px] rounded-[7px] border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer"
              >
                Copy
              </button>
            </div>
            <p class="mt-2 text-[10px] text-gray-400">
              Use this key to authenticate WebSocket or REST API requests.
            </p>
          </div>
        </div>

        <%!-- Passkeys section --%>
        <div
          class="mb-5 rounded-[10px] border bg-white dark:bg-[#1a1f2e]"
          style="border-color: #e5e7eb"
        >
          <div class="px-4 py-3 border-b" style="border-color: #e5e7eb">
            <h2 class="text-[12px] font-semibold text-gray-700 dark:text-gray-300">Passkeys</h2>
          </div>
          <%!-- PasskeyRegister hook anchor (invisible) --%>
          <div id="passkey-register-hook" phx-hook="PasskeyRegister" style="display:none" />
          <%!-- Error message --%>
          <p
            :if={@passkey_error}
            role="alert"
            class="mx-4 mt-3 text-[11px] text-red-500"
          >
            {@passkey_error}
          </p>
          <%!-- Empty state --%>
          <div :if={@passkeys == []} class="p-4 flex items-start gap-3">
            <div style="width:36px;height:36px;border-radius:8px;background:#eff6ff;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
              <svg style="width:18px;height:18px;" fill="none" stroke="#2563eb" viewBox="0 0 24 24" aria-hidden="true">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
                />
              </svg>
            </div>
            <div style="flex:1;">
              <p class="text-[12px] font-semibold text-gray-900 dark:text-gray-100 mb-1">
                Add a passkey
              </p>
              <p class="text-[11px] text-gray-500" style="line-height:1.5;max-width:380px;">
                Sign in faster and more securely using biometrics or your device PIN — no password required.
              </p>
            </div>
            <button
              type="button"
              phx-click="add_passkey"
              style="display:flex;align-items:center;gap:4px;height:28px;padding:0 10px;font-size:11px;font-weight:500;border:1px solid #2563eb;color:#2563eb;border-radius:6px;background:transparent;cursor:pointer;white-space:nowrap;"
              aria-label="Add a passkey for passwordless sign-in"
            >
              <svg style="width:12px;height:12px;" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
              </svg>
              Add passkey
            </button>
          </div>
          <%!-- Passkey list --%>
          <div :if={@passkeys != []}>
            <div :for={pk <- @passkeys} class="flex items-center gap-2 px-4 py-2.5 border-b" style="border-color: #f3f4f6;">
              <svg style="width:14px;height:14px;flex-shrink:0;" fill="none" stroke="#6b7280" viewBox="0 0 24 24" aria-hidden="true">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
              <div style="flex:1;">
                <p class="text-[11px] font-medium text-gray-900 dark:text-gray-100">{pk.label}</p>
                <p class="text-[10px] text-gray-400">
                  Added {format_passkey_date(pk.created_at)}
                </p>
              </div>
              <button
                type="button"
                phx-click="delete_passkey"
                phx-value-id={pk.id}
                style="display:flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:4px;border:none;background:transparent;cursor:pointer;"
                aria-label={"Remove passkey: #{pk.label}"}
              >
                <svg style="width:13px;height:13px;" fill="none" stroke="#ef4444" viewBox="0 0 24 24" aria-hidden="true">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                  />
                </svg>
              </button>
            </div>
            <div class="px-4 py-2">
              <button
                type="button"
                phx-click="add_passkey"
                class="text-[11px] text-blue-600 dark:text-blue-400"
                style="border:none;background:transparent;cursor:pointer;"
                aria-label="Add another passkey"
              >
                + Add another passkey
              </button>
            </div>
          </div>
        </div>

        <%!-- System info section --%>
        <div
          class="rounded-[10px] border bg-white dark:bg-[#1a1f2e]"
          style="border-color: #e5e7eb"
        >
          <div class="px-5 py-[14px] border-b" style="border-color: #f3f4f6">
            <h2 class="text-[13px] font-semibold text-gray-900 dark:text-gray-100">
              System Info
            </h2>
          </div>
          <div class="px-5 divide-y divide-gray-100 dark:divide-gray-700">
            <%= for {label, value} <- system_info_rows(@system_info) do %>
              <div class="flex items-center justify-between py-2">
                <span class="text-[11px] text-gray-500">{label}</span>
                <code class="text-[11px] font-mono text-gray-700 dark:text-gray-300">{value}</code>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @spec build_system_info() :: map()
  defp build_system_info do
    %{
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> to_string(),
      phoenix: Application.spec(:phoenix, :vsn) |> to_string(),
      taniwha: Application.spec(:taniwha, :vsn) |> to_string()
    }
  end

  @spec check_connection() :: :ok | :error
  defp check_connection do
    case Process.whereis(Taniwha.RPC.Client) do
      nil -> :error
      pid -> if Process.alive?(pid), do: :ok, else: :error
    end
  end

  @spec format_passkey_date(String.t()) :: String.t()
  defp format_passkey_date(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _offset} ->
        month = Calendar.strftime(dt, "%b")
        day = dt.day
        year = dt.year
        "#{month} #{day}, #{year}"

      _ ->
        iso8601
    end
  end

  @spec system_info_rows(map()) :: [{String.t(), String.t()}]
  defp system_info_rows(info) do
    [
      {"Elixir", info.elixir},
      {"OTP", info.otp},
      {"Phoenix", info.phoenix},
      {"Taniwha", info.taniwha}
    ]
  end
end
