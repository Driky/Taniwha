defmodule TaniwhaWeb.Plugs.RateLimit do
  @moduledoc """
  Plug that enforces a sliding-window rate limit per client IP address.

  Uses `Taniwha.RateLimiter` for ETS-backed counter management. When the limit
  is exceeded the request is halted with a **429 Too Many Requests** JSON
  response and a `Retry-After` header.

  ## Options

    * `:limit` — maximum requests allowed per window (default from app config,
      falls back to `10`)
    * `:window_ms` — window size in milliseconds (default from app config,
      falls back to `60_000`)

  ## Usage

      # In a pipeline:
      pipeline :api_auth do
        plug :accepts, ["json"]
        plug TaniwhaWeb.Plugs.RateLimit
      end

      # With explicit options:
      plug TaniwhaWeb.Plugs.RateLimit, limit: 5, window_ms: 30_000
  """

  @behaviour Plug

  import Plug.Conn

  @rate_limited_body Jason.encode!(%{error: "rate_limited"})

  @impl Plug
  def init(opts) do
    limit = Keyword.get(opts, :limit, Application.get_env(:taniwha, :rate_limit_max, 10))

    window_ms =
      Keyword.get(opts, :window_ms, Application.get_env(:taniwha, :rate_limit_window_ms, 60_000))

    %{limit: limit, window_ms: window_ms}
  end

  @impl Plug
  def call(conn, %{limit: limit, window_ms: window_ms}) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    bucket = {:auth_token, ip}

    case Taniwha.RateLimiter.check_and_increment(bucket, limit, window_ms) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        retry_after = div(window_ms, 1_000) |> to_string()

        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("retry-after", retry_after)
        |> send_resp(429, @rate_limited_body)
        |> halt()
    end
  end
end
