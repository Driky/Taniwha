defmodule TaniwhaWeb.HealthControllerTest do
  use TaniwhaWeb.ConnCase, async: false

  import Mox

  alias Taniwha.MockCommands

  setup :set_mox_from_context
  setup :verify_on_exit!

  # ── Batch 1: response shape ───────────────────────────────────────────────────

  describe "GET /health" do
    test "returns 200 with connected status when rtorrent responds", %{conn: conn} do
      expect(MockCommands, :system_pid, fn -> {:ok, 12_345} end)
      conn = get(conn, "/health")

      assert %{"status" => "ok", "rtorrent" => "connected"} = json_response(conn, 200)
    end

    test "returns 200 with disconnected status when rtorrent is unreachable", %{conn: conn} do
      expect(MockCommands, :system_pid, fn -> {:error, :connection_refused} end)
      conn = get(conn, "/health")

      assert %{"status" => "ok", "rtorrent" => "disconnected"} = json_response(conn, 200)
    end

    test "does not require authentication", %{conn: conn} do
      expect(MockCommands, :system_pid, fn -> {:ok, 1} end)
      # No Authorization header — must still succeed
      conn = get(conn, "/health")
      assert conn.status == 200
    end
  end
end
