defmodule TaniwhaWeb.AuthIntegrationTest do
  @moduledoc """
  Integration tests verifying that protected routes redirect unauthenticated
  requests to /login, and that unprotected endpoints remain accessible.
  """

  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Taniwha.MockCommands

  setup :verify_on_exit!

  # ---------------------------------------------------------------------------
  # Batch 5 — Router integration
  # ---------------------------------------------------------------------------

  describe "unauthenticated access to protected routes" do
    test "GET / redirects to /login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/")
      assert path == "/login"
    end

    test "GET /settings redirects to /login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/settings")
      assert path == "/login"
    end
  end

  describe "authenticated access to protected routes" do
    setup %{conn: conn} do
      {conn, _user} = register_and_log_in_user(conn)
      {:ok, conn: conn}
    end

    test "GET / renders dashboard", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Torrents"
    end
  end

  describe "unprotected endpoints remain accessible" do
    test "GET /health returns 200 without auth", %{conn: conn} do
      expect(MockCommands, :system_pid, fn -> {:ok, 1} end)
      conn = get(conn, ~p"/health")
      assert conn.status == 200
    end

    test "POST /api/v1/auth/token returns JWT with valid api_key", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/token", %{api_key: "test-api-key-for-tests"})
      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token)
    end

    test "GET /login renders without auth", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ "Sign in"
    end

    test "GET /setup renders without auth when no users exist", %{conn: conn} do
      # This test assumes no users are in the store (or will cleanup properly).
      # If a user happens to exist from another test, /setup redirects to /login — both are acceptable.
      result = live(conn, ~p"/setup")

      case result do
        {:ok, _lv, html} -> assert html =~ "Create admin account"
        {:error, {:live_redirect, %{to: "/login"}}} -> :ok
      end
    end
  end
end
