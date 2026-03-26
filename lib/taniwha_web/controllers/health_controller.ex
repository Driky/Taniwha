defmodule TaniwhaWeb.HealthController do
  @moduledoc """
  Unauthenticated health check endpoint.

  Returns HTTP 200 in all cases (including when rtorrent is unreachable) so
  that load balancers and process supervisors always see the Phoenix application
  as healthy. The `rtorrent` field in the response body conveys the actual
  connectivity status for human operators and monitoring dashboards.

  ## Response

      GET /health

      200 OK
      {"status": "ok", "rtorrent": "connected"}   # rtorrent is reachable
      {"status": "ok", "rtorrent": "disconnected"} # rtorrent is not reachable

  See `docs/server-setup.md` for monitoring configuration examples.
  """

  use TaniwhaWeb, :controller

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  @doc "Returns the application health status."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    rtorrent_status =
      case @commands.system_pid() do
        {:ok, _} -> "connected"
        {:error, _} -> "disconnected"
      end

    json(conn, %{status: "ok", rtorrent: rtorrent_status})
  end
end
