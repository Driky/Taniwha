defmodule TaniwhaWeb.Router do
  use TaniwhaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TaniwhaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Rate-limited pipeline for the token exchange endpoint. Prevents brute-force
  # enumeration of the TANIWHA_API_KEY by capping attempts per client IP.
  pipeline :api_auth do
    plug :accepts, ["json"]
    plug TaniwhaWeb.Plugs.RateLimit
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug TaniwhaWeb.Plugs.AuthenticateToken
  end

  # Authenticates browser requests via session cookie. Applied only to the
  # protected browser scope below — not to the API or health check pipelines.
  pipeline :browser_auth do
    plug TaniwhaWeb.Plugs.AuthenticateSession
  end

  # Unauthenticated browser routes: login, setup, session management.
  scope "/", TaniwhaWeb do
    pipe_through :browser

    live_session :unauthenticated,
      on_mount: [{TaniwhaWeb.UserAuth, :redirect_if_authenticated}] do
      live "/login", LoginLive, :index
    end

    # Setup does its own redirect check in mount (guarded against race conditions).
    live "/setup", SetupLive, :index

    post "/session", SessionController, :create
    post "/session/passkey", SessionController, :create_from_passkey
    delete "/session", SessionController, :delete
  end

  # Protected browser routes — require a valid session cookie.
  scope "/", TaniwhaWeb do
    pipe_through [:browser, :browser_auth]

    live_session :authenticated,
      on_mount: [{TaniwhaWeb.UserAuth, :require_authenticated_user}] do
      live "/", DashboardLive, :index
      live "/torrents/:hash", TorrentDetailLive, :show
      live "/add", AddTorrentLive, :new
      live "/settings", SettingsLive, :index
    end
  end

  # Health check — unauthenticated, no CSRF, no session. Intended for load
  # balancers and monitoring. Always returns 200 with rtorrent connectivity status.
  scope "/", TaniwhaWeb do
    get "/health", HealthController, :show
  end

  scope "/api/v1", TaniwhaWeb.API do
    pipe_through :api_auth

    post "/auth/token", AuthController, :create
  end

  scope "/api/v1", TaniwhaWeb.API do
    pipe_through :api_authenticated

    get "/torrents", TorrentController, :index
    get "/torrents/:hash", TorrentController, :show
    post "/torrents", TorrentController, :create
    delete "/torrents/:hash", TorrentController, :delete

    get "/throttle", ThrottleController, :show
    put "/throttle/download", ThrottleController, :set_download
    put "/throttle/upload", ThrottleController, :set_upload
    put "/throttle/presets", ThrottleController, :set_presets
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:taniwha, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TaniwhaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
