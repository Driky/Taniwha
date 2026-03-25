import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/taniwha start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :taniwha, TaniwhaWeb.Endpoint, server: true
end

config :taniwha, TaniwhaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # ---------------------------------------------------------------------------
  # OpenTelemetry — vendor-agnostic tracing via OTLP (production only).
  # Dev uses the stdout exporter (see config/dev.exs).
  # Test uses the simple processor with no exporter (see config/test.exs).
  # All settings are driven by environment variables; no values are hardcoded.
  #
  # Supported OTEL_* environment variables:
  #   OTEL_SERVICE_NAME             Service name in traces (default: "taniwha")
  #   OTEL_EXPORTER_OTLP_ENDPOINT   Collector URL (default: http://localhost:4318)
  #   OTEL_EXPORTER_OTLP_PROTOCOL   "http_protobuf" or "grpc" (default: http_protobuf)
  #   OTEL_EXPORTER_OTLP_HEADERS    Auth headers, e.g. "signoz-ingestion-key=<key>"
  #   OTEL_TRACES_SAMPLER           Set "always_off" to disable tracing entirely
  # ---------------------------------------------------------------------------
  otel_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

  otel_protocol =
    case System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL", "http_protobuf") do
      "grpc" -> :grpc
      _ -> :http_protobuf
    end

  config :opentelemetry,
    resource: [service: [name: System.get_env("OTEL_SERVICE_NAME", "taniwha")]],
    processors: [
      otel_batch_processor: %{
        exporter: {
          :opentelemetry_exporter,
          %{protocol: otel_protocol, endpoints: [otel_endpoint]}
        }
      }
    ]

  # Note: OTEL_EXPORTER_OTLP_HEADERS is read natively by opentelemetry_exporter
  # following the OTel spec — no manual parsing is required.

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :taniwha, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  api_key =
    System.get_env("TANIWHA_API_KEY") ||
      raise "environment variable TANIWHA_API_KEY is missing."

  config :taniwha, api_key: api_key

  socket_path = System.get_env("RTORRENT_SOCKET", "/var/run/rtorrent.sock")
  config :taniwha, scgi_transport: {:unix, socket_path}

  config :taniwha, TaniwhaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :taniwha, TaniwhaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :taniwha, TaniwhaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :taniwha, Taniwha.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
