import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :taniwha, TaniwhaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "j4N2zfKy3HPsVP3/4vWVoI/oYn/rzAPx2aqeGwsJnptrc1g6i4jRAZoI6QCMmlON",
  server: false

# In test we don't send emails
config :taniwha, Taniwha.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :taniwha,
  scgi_connection: Taniwha.SCGI.MockConnection,
  scgi_transport: {:unix, "/tmp/rtorrent_test.sock"},
  scgi_timeout: 5_000,
  rpc_client: Taniwha.RPC.MockClient,
  commands: Taniwha.MockCommands,
  poll_interval: 86_400_000

config :taniwha, api_key: "test-api-key-for-tests"

# OpenTelemetry: run the simple processor (required for span-capture tests to call
# set_exporter/2) but set no exporter, so spans are dropped by default.
# Individual tests override via :otel_simple_processor.set_exporter/2.
config :opentelemetry, processors: [{:otel_simple_processor, %{}}]

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
