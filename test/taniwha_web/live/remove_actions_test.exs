defmodule TaniwhaWeb.Live.RemoveActionsTest do
  @moduledoc false
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Taniwha.{MockCommands, State.Store}
  alias Taniwha.Test.Fixtures

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Store.clear()
    on_exit(fn -> Store.clear() end)
    :ok
  end

  setup %{conn: conn} do
    {conn, _user} = register_and_log_in_user(conn)
    {:ok, conn: conn}
  end

  # ---------------------------------------------------------------------------
  # Batch 1 — context_menu_action "erase_with_data"
  # ---------------------------------------------------------------------------

  describe "context_menu_action erase_with_data" do
    test "single hash sets confirm_action with base_path from torrent", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture("hash1") | base_path: "/downloads/mytorrent"}
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv
      |> element("#torrent-tbody")
      |> render_hook("context_menu_action", %{
        "action" => "erase_with_data",
        "hashes" => ["hash1"]
      })

      html = render(lv)
      # Dialog should appear with the file-delete variant
      assert html =~ "delete files"
      assert html =~ "/downloads/mytorrent"
    end

    test "multiple hashes sets bulk confirm_action", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("hash1") | base_path: "/downloads/t1"}
      t2 = %{Fixtures.torrent_fixture("hash2") | base_path: "/downloads/t2"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv
      |> element("#torrent-tbody")
      |> render_hook("context_menu_action", %{
        "action" => "erase_with_data",
        "hashes" => ["hash1", "hash2"]
      })

      html = render(lv)
      assert html =~ "delete files"
      assert html =~ "2 torrents"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — confirm_action for erase_with_data
  # ---------------------------------------------------------------------------

  describe "confirm_action erase_with_data" do
    test "calls erase_with_data and removes torrent from assigns", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture("hash1") | base_path: "/downloads/mytorrent"}
      Store.put_torrent(torrent)

      expect(MockCommands, :erase_with_data, fn "hash1" -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")

      # Set the confirm_action state via context menu
      lv
      |> element("#torrent-tbody")
      |> render_hook("context_menu_action", %{
        "action" => "erase_with_data",
        "hashes" => ["hash1"]
      })

      # Confirm the action
      html = lv |> element("button[phx-click=confirm_action]") |> render_click()
      assert html =~ "removed"
      refute html =~ torrent.name
    end

    test "bulk erase_with_data calls erase_many_with_data", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("hash1") | base_path: "/downloads/t1"}
      t2 = %{Fixtures.torrent_fixture("hash2") | base_path: "/downloads/t2"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      expect(MockCommands, :erase_many_with_data, fn hashes ->
        assert Enum.sort(hashes) == ["hash1", "hash2"]
        {:ok, hashes, []}
      end)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv
      |> element("#torrent-tbody")
      |> render_hook("context_menu_action", %{
        "action" => "erase_with_data",
        "hashes" => ["hash1", "hash2"]
      })

      lv |> element("button[phx-click=confirm_action]") |> render_click()
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — bulk_remove_with_data toolbar event
  # ---------------------------------------------------------------------------

  describe "bulk_remove_with_data" do
    test "sets confirm_action for selected hashes", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture("hash1") | base_path: "/downloads/mytorrent"}
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      # Select the torrent first
      lv
      |> element("#torrent-tbody")
      |> render_hook("update_selection", %{
        "hashes" => ["hash1"],
        "focused_hash" => "hash1"
      })

      lv |> element("#torrent-tbody") |> render_hook("bulk_remove_with_data", %{})

      html = render(lv)
      assert html =~ "delete files"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — confirmation_dialog renders correct variant
  # ---------------------------------------------------------------------------

  describe "confirmation_dialog variants" do
    test "erase_with_data dialog shows Delete files button, not Remove", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture("hash1") | base_path: "/downloads/mytorrent"}
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv
      |> element("#torrent-tbody")
      |> render_hook("context_menu_action", %{
        "action" => "erase_with_data",
        "hashes" => ["hash1"]
      })

      html = render(lv)
      assert html =~ "Delete files"
      assert html =~ "This cannot be undone"
      assert html =~ "/downloads/mytorrent"
    end

    test "regular erase dialog still shows Remove button", %{conn: conn} do
      torrent = Fixtures.torrent_fixture("hash1")
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv
      |> element("#torrent-tbody")
      |> render_hook("context_menu_action", %{
        "action" => "erase",
        "hashes" => ["hash1"]
      })

      html = render(lv)
      assert html =~ "Remove"
      refute html =~ "Delete files"
    end
  end
end
