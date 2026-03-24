defmodule TaniwhaWeb.SettingsLive do
  @moduledoc """
  Settings page LiveView.

  Displays connection status, API key (masked by default with reveal/copy
  actions), and system version information.
  """

  use TaniwhaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:api_key_revealed, false)
     |> assign(:api_key, Application.get_env(:taniwha, :api_key, ""))
     |> assign(:system_info, build_system_info())
     |> assign(:connection_status, check_connection())}
  end

  @impl true
  def handle_event("reveal_key", _params, socket) do
    {:noreply, assign(socket, :api_key_revealed, !socket.assigns.api_key_revealed)}
  end

  def handle_event("copy_key", _params, socket) do
    {:noreply, push_event(socket, "copy-to-clipboard", %{text: socket.assigns.api_key})}
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
          <.icon name="hero-arrow-left-mini" class="size-4" />
          Dashboard
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
              <%= if @connection_status == :ok, do: "Connected", else: "Not connected" %>
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
                <%= if @api_key_revealed, do: @api_key, else: String.duplicate("•", min(String.length(@api_key), 32)) %>
              </code>
              <button
                type="button"
                phx-click="reveal_key"
                aria-label={if @api_key_revealed, do: "Hide API key", else: "Reveal API key"}
                aria-pressed={to_string(@api_key_revealed)}
                class="shrink-0 px-3 py-1.5 text-[11px] rounded-[7px] border border-gray-200 dark:border-gray-600 text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer"
              >
                <%= if @api_key_revealed, do: "Hide", else: "Reveal" %>
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
