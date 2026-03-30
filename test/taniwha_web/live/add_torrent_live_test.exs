defmodule TaniwhaWeb.AddTorrentLiveTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {conn, _user} = register_and_log_in_user(conn)
    {:ok, conn: conn}
  end

  describe "GET /add" do
    test "redirects to the dashboard", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/add")
    end
  end
end
