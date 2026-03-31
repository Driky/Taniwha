defmodule Taniwha.Application do
  @moduledoc "OTP Application entry point. Custom children wired in later tasks."
  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    # Attach OpenTelemetry telemetry handlers before any supervised process starts.
    # These hook into :telemetry events emitted by Bandit and Phoenix, producing
    # HTTP request and LiveView spans automatically.
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryLoggerMetadata.setup()

    check_runtime_warnings()

    children = [
      {Phoenix.PubSub, name: Taniwha.PubSub},
      # RateLimiter must start before TaniwhaWeb.Endpoint so the first HTTP
      # request can never arrive before the ETS table is ready.
      Taniwha.RateLimiter,
      # CredentialStore must start before TaniwhaWeb.Endpoint so auth routes
      # are operational from the first HTTP request.
      Taniwha.Auth.CredentialStore,
      # LabelStore must start before TaniwhaWeb.Endpoint so label colours are
      # available when the first LiveView renders.
      Taniwha.LabelStore,
      Taniwha.RPC.Client,
      Taniwha.State.Store,
      Taniwha.State.Poller,
      TaniwhaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Taniwha.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TaniwhaWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  # Emits Logger warnings for non-fatal configuration issues that are likely to
  # cause problems at runtime. Hard failures (missing TANIWHA_API_KEY, missing
  # SECRET_KEY_BASE) are raised earlier in config/runtime.exs.
  #
  # See also: config/runtime.exs for the full list of required env vars.
  # `:env` is set in config.exs as `config_env()` — compile-time constant.
  @prod_build Application.compile_env(:taniwha, :env, :prod) == :prod

  @spec check_runtime_warnings() :: :ok
  defp check_runtime_warnings do
    if @prod_build do
      case Application.get_env(:taniwha, :scgi_transport) do
        {:unix, path} ->
          unless File.exists?(path) do
            Logger.warning(
              "rtorrent socket not found at #{path}; " <>
                "Taniwha will retry on each RPC call once rtorrent is running"
            )
          end

        _ ->
          :ok
      end

      unless System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
        Logger.warning(
          "OTEL_EXPORTER_OTLP_ENDPOINT is not set; " <>
            "defaulting to http://localhost:4318 — set this to your collector URL"
        )
      end
    end

    :ok
  end
end
