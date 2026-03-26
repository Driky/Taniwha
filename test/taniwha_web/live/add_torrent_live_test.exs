defmodule TaniwhaWeb.AddTorrentLiveTest do
  use TaniwhaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /add" do
    test "redirects to the dashboard", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/add")
    end
  end
end
