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

config :taniwha, scgi_connection: Taniwha.SCGI.MockConnection

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
