defmodule TaniwhaWeb.AddTorrentLive do
  @moduledoc """
  Redirects to the dashboard. The add-torrent form is now an embedded modal
  in `DashboardLive` — this route exists for backwards compatibility.
  """
  use TaniwhaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    """
  end
end
