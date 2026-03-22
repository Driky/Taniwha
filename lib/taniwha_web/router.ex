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

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug TaniwhaWeb.Plugs.AuthenticateToken
  end

  scope "/", TaniwhaWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api/v1", TaniwhaWeb.API do
    pipe_through :api

    post "/auth/token", AuthController, :create
  end

  scope "/api/v1", TaniwhaWeb.API do
    pipe_through :api_authenticated

    get "/torrents", TorrentController, :index
    get "/torrents/:hash", TorrentController, :show
    post "/torrents", TorrentController, :create
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
