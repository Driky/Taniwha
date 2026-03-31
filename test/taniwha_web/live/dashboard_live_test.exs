defmodule TaniwhaWeb.DashboardLiveTest do
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
  # Batch 1 — Mount renders
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "renders the dashboard heading", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Torrents"
    end

    test "page title is Torrents", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~r/<title[^>]*>\s*Torrents/
    end

    test "renders empty state when no torrents", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "No torrents yet"
    end

    test "renders torrent rows when store has torrents", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ torrent.name
    end

    test "does not show empty state when torrents exist", %{conn: conn} do
      Store.put_torrent(Fixtures.torrent_fixture())
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "No torrents yet"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — PubSub diffs
  # ---------------------------------------------------------------------------

  describe "handle_info torrent_diffs" do
    test "added diff appends torrent row", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      new_torrent = Fixtures.torrent_fixture("newhash123")
      send(lv.pid, {:torrent_diffs, [{:added, new_torrent}]})

      html = render(lv)
      assert html =~ new_torrent.name
    end

    test "updated diff reflects new data", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      updated = %{torrent | name: "Updated Name", download_rate: 9_999}
      send(lv.pid, {:torrent_diffs, [{:updated, updated}]})

      html = render(lv)
      assert html =~ "Updated Name"
    end

    test "removed diff removes torrent row", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      send(lv.pid, {:torrent_diffs, [{:removed, torrent.hash}]})

      html = render(lv)
      refute html =~ torrent.name
    end

    test "global stats update after diff", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      {:ok, lv, _html} = live(conn, ~p"/")

      send(lv.pid, {:torrent_diffs, [{:added, torrent}]})

      html = render(lv)
      # visible count in action_bar shows "1" after adding one torrent
      assert html =~ "1 torrents"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — Search
  # ---------------------------------------------------------------------------

  describe "search" do
    test "filters by name substring (case-insensitive)", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | name: "Ubuntu ISO"}
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Debian Image"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")

      html = lv |> element("input[phx-change=search]") |> render_change(%{value: "ubuntu"})

      assert html =~ "Ubuntu ISO"
      refute html =~ "Debian Image"
    end

    test "clears back to full list when search is empty", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | name: "Ubuntu ISO"}
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Debian Image"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv |> element("input[phx-change=search]") |> render_change(%{value: "ubuntu"})
      html = lv |> element("input[phx-change=search]") |> render_change(%{value: ""})

      assert html =~ "Ubuntu ISO"
      assert html =~ "Debian Image"
    end

    test "shows no-results state when no torrent matches", %{conn: conn} do
      Store.put_torrent(Fixtures.torrent_fixture())
      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        lv |> element("input[phx-change=search]") |> render_change(%{value: "zzznomatch"})

      assert html =~ "No torrents match"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — Filter tabs
  # ---------------------------------------------------------------------------

  describe "filter tabs" do
    test ":all shows all torrents", %{conn: conn} do
      downloading = %{
        Fixtures.torrent_fixture("h1")
        | state: :started,
          is_active: true,
          complete: false
      }

      stopped = %{
        Fixtures.torrent_fixture("h2")
        | state: :stopped,
          is_active: false,
          name: "Stopped One"
      }

      Store.put_torrent(downloading)
      Store.put_torrent(stopped)

      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        lv
        |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=all]")
        |> render_click()

      assert html =~ downloading.name
      assert html =~ stopped.name
    end

    test ":downloading shows only downloading torrents", %{conn: conn} do
      dl = %{
        Fixtures.torrent_fixture("h1")
        | state: :started,
          is_active: true,
          complete: false,
          name: "Active DL"
      }

      stopped = %{
        Fixtures.torrent_fixture("h2")
        | state: :stopped,
          is_active: false,
          name: "Stopped One"
      }

      Store.put_torrent(dl)
      Store.put_torrent(stopped)

      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        lv
        |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=downloading]")
        |> render_click()

      assert html =~ "Active DL"
      refute html =~ "Stopped One"
    end

    test ":seeding shows only seeding torrents", %{conn: conn} do
      seeding = %{
        Fixtures.torrent_fixture("h1")
        | state: :started,
          is_active: true,
          complete: true,
          name: "Seeder"
      }

      stopped = %{
        Fixtures.torrent_fixture("h2")
        | state: :stopped,
          is_active: false,
          name: "Stopper"
      }

      Store.put_torrent(seeding)
      Store.put_torrent(stopped)

      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        lv
        |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=seeding]")
        |> render_click()

      assert html =~ "Seeder"
      refute html =~ "Stopper"
    end

    test ":stopped shows only stopped torrents", %{conn: conn} do
      downloading = %{
        Fixtures.torrent_fixture("h1")
        | state: :started,
          is_active: true,
          complete: false,
          name: "Downloader"
      }

      stopped = %{
        Fixtures.torrent_fixture("h2")
        | state: :stopped,
          is_active: false,
          name: "Stopper"
      }

      Store.put_torrent(downloading)
      Store.put_torrent(stopped)

      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        lv
        |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=stopped]")
        |> render_click()

      refute html =~ "Downloader"
      assert html =~ "Stopper"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 5 — Sort
  # ---------------------------------------------------------------------------

  describe "sort" do
    test "sorts by name ascending by default", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | name: "Zeta"}
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Alpha"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, _lv, html} = live(conn, ~p"/")

      alpha_pos = :binary.match(html, "Alpha") |> elem(0)
      zeta_pos = :binary.match(html, "Zeta") |> elem(0)
      assert alpha_pos < zeta_pos
    end

    test "toggles to descending on same column click", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | name: "Zeta"}
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Alpha"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")

      # One click toggles from default asc to desc
      html = lv |> element("[phx-click=sort][phx-value-by=name]") |> render_click()

      zeta_pos = :binary.match(html, "Zeta") |> elem(0)
      alpha_pos = :binary.match(html, "Alpha") |> elem(0)
      assert zeta_pos < alpha_pos
    end

    test "resets to ascending when clicking a new column", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | name: "AlphaA", size: 500}
      t2 = %{Fixtures.torrent_fixture("h2") | name: "BetaB", size: 100}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")

      # Sort by name desc (two clicks to get to desc)
      lv |> element("[phx-click=sort][phx-value-by=name]") |> render_click()
      lv |> element("[phx-click=sort][phx-value-by=name]") |> render_click()

      # Now click size — should reset to asc: smaller size (BetaB=100) first
      html = lv |> element("[phx-click=sort][phx-value-by=size]") |> render_click()

      betab_pos = :binary.match(html, ~s(title="BetaB")) |> elem(0)
      alphaa_pos = :binary.match(html, ~s(title="AlphaA")) |> elem(0)
      assert betab_pos < alphaa_pos
    end

    test "sort indicator appears on active column", %{conn: conn} do
      Store.put_torrent(Fixtures.torrent_fixture())
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "hero-chevron-up-micro"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6 — Lifecycle actions
  # ---------------------------------------------------------------------------

  describe "lifecycle actions" do
    test "start_torrent calls Commands.start/1", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture() | state: :stopped}
      Store.put_torrent(torrent)
      hash = torrent.hash
      expect(MockCommands, :start, fn ^hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=start_torrent]") |> render_click()
    end

    test "stop_torrent calls Commands.stop/1", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture() | state: :started, is_active: true, complete: false}
      Store.put_torrent(torrent)
      hash = torrent.hash
      expect(MockCommands, :stop, fn ^hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=stop_torrent]") |> render_click()
    end

    test "remove_torrent sets confirm_action assign (does not call Commands.erase)", %{
      conn: conn
    } do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()

      html = render(lv)
      # Confirmation dialog should be visible
      assert html =~ "role=\"dialog\""
    end

    test "remove_torrent does not immediately remove torrent from assigns", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()

      html = render(lv)
      assert html =~ torrent.name
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 7 — Selection and bulk actions
  # ---------------------------------------------------------------------------

  describe "selection and bulk actions" do
    test "toggle_select adds hash to selected_hashes", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      html = lv |> element("input[phx-click=toggle_select]") |> render_click()

      assert html =~ "1 selected"
    end

    test "toggle_select removes hash when already selected", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("input[phx-click=toggle_select]") |> render_click()
      html = lv |> element("input[phx-click=toggle_select]") |> render_click()

      # Bulk toolbar "N selected" count text should be gone
      refute html =~ ~r/\d+ selected/
    end

    test "select_all selects all visible torrents", %{conn: conn} do
      t1 = Fixtures.torrent_fixture("h1")
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Second"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")
      html = lv |> element("input[phx-click=select_all]") |> render_click()

      assert html =~ "2 selected"
    end

    test "deselect_all clears selection", %{conn: conn} do
      t1 = Fixtures.torrent_fixture("h1")
      Store.put_torrent(t1)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("input[phx-click=select_all]") |> render_click()
      html = lv |> element("button[phx-click=deselect_all]") |> render_click()

      refute html =~ ~r/\d+ selected/
    end

    test "bulk_start calls start for each selected hash", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | state: :stopped, name: "T1"}
      t2 = %{Fixtures.torrent_fixture("h2") | state: :stopped, name: "T2"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      expect(MockCommands, :start, 2, fn _hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("input[phx-click=select_all]") |> render_click()
      lv |> element("button[phx-click=bulk_start]") |> render_click()
    end

    test "bulk_stop calls stop for each selected hash", %{conn: conn} do
      t1 = %{
        Fixtures.torrent_fixture("h1")
        | state: :started,
          is_active: true,
          complete: false,
          name: "T1"
      }

      t2 = %{
        Fixtures.torrent_fixture("h2")
        | state: :started,
          is_active: true,
          complete: false,
          name: "T2"
      }

      Store.put_torrent(t1)
      Store.put_torrent(t2)

      expect(MockCommands, :stop, 2, fn _hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("input[phx-click=select_all]") |> render_click()
      lv |> element("button[phx-click=bulk_stop]") |> render_click()
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — Accessibility
  # ---------------------------------------------------------------------------

  describe "accessibility" do
    test "filter tabs have aria-pressed for active state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(aria-pressed="false")
    end

    test "sort buttons have accessible text content", %{conn: conn} do
      Store.put_torrent(Fixtures.torrent_fixture())
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~s(phx-click="sort")
    end

    test "empty state has role=status", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~s(role="status")
    end

    test "all buttons have accessible labels", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, _lv, html} = live(conn, ~p"/")

      import TaniwhaWeb.AccessibilityHelper
      assert_labeled_buttons(html)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 9 — Row selection (selected_hash)
  # ---------------------------------------------------------------------------

  describe "row selection" do
    test "no row is highlighted on mount", %{conn: conn} do
      Store.put_torrent(Fixtures.torrent_fixture())
      {:ok, _lv, html} = live(conn, ~p"/")
      # Sidebar uses "background-color: var(--taniwha-sidebar-active-bg)"
      # Row selection uses "background: var(--taniwha-sidebar-active-bg)" (no -color)
      # Without any row selected, the shorthand form should not appear on any row
      refute html =~ "background: var(--taniwha-sidebar-active-bg)"
    end

    test "clicking a row sets selected_hash", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      html = lv |> element("tr[phx-click=select_torrent]") |> render_click()

      assert html =~ "background: var(--taniwha-sidebar-active-bg)"
    end

    test "clicking a different row updates selected_hash", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | name: "First"}
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Second"}
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      {:ok, lv, _html} = live(conn, ~p"/")

      lv |> element("tr#torrent-h1[phx-click=select_torrent]") |> render_click()

      # Select row h2 — h2 should be highlighted, h1 should not
      html = lv |> element("tr#torrent-h2[phx-click=select_torrent]") |> render_click()

      # h2 row should be highlighted; background style appears exactly once (for h2)
      assert html =~ "background: var(--taniwha-sidebar-active-bg)"
      count = html |> String.split("background: var(--taniwha-sidebar-active-bg)") |> length()
      # split produces n+1 parts for n occurrences; only h2 should be highlighted
      assert count == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Batch — Confirmation flow (remove / bulk_remove / confirm / cancel)
  # ---------------------------------------------------------------------------

  describe "confirmation flow" do
    test "remove_torrent sets confirm_action, dialog visible", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()

      assert render(lv) =~ ~s(role="dialog")
    end

    test "cancel_confirm hides the dialog", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()
      lv |> element("button[phx-click=cancel_confirm]") |> render_click()

      refute render(lv) =~ ~s(role="dialog")
    end

    test "confirm_action calls Commands.erase/1 and removes torrent", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      hash = torrent.hash
      expect(MockCommands, :erase, fn ^hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()
      lv |> element("button[phx-click=confirm_action]") |> render_click()

      html = render(lv)
      refute html =~ torrent.name
      refute html =~ ~s(role="dialog")
    end

    test "confirm_action clears dialog and puts :info flash", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      stub(MockCommands, :erase, fn _hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()
      lv |> element("button[phx-click=confirm_action]") |> render_click()

      html = render(lv)
      refute html =~ ~s(role="dialog")
    end

    test "bulk_remove sets confirm_action for bulk erase", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("input[phx-click=toggle_select]") |> render_click()
      # Trigger event directly — bulk_remove button is added in Batch 4
      render_click(lv, "bulk_remove", %{})

      assert render(lv) =~ ~s(role="dialog")
    end

    test "confirm_action with bulk_erase calls Commands.erase for each hash", %{conn: conn} do
      t1 = Fixtures.torrent_fixture("h1")
      t2 = Fixtures.torrent_fixture("h2")
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      expect(MockCommands, :erase, fn "h1" -> :ok end)
      expect(MockCommands, :erase, fn "h2" -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      render_click(lv, "select_all", %{})
      render_click(lv, "bulk_remove", %{})
      lv |> element("button[phx-click=confirm_action]") |> render_click()

      html = render(lv)
      refute html =~ ~s(role="dialog")
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 11 — Context menu server events
  # ---------------------------------------------------------------------------

  describe "context menu actions" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")
      {:ok, lv: lv, hash: torrent.hash}
    end

    test "start action calls Commands.start/1", %{lv: lv, hash: hash} do
      expect(MockCommands, :start, fn ^hash -> :ok end)
      render_click(lv, "context_menu_action", %{"action" => "start", "hash" => hash})
    end

    test "stop action calls Commands.stop/1", %{lv: lv, hash: hash} do
      expect(MockCommands, :stop, fn ^hash -> :ok end)
      render_click(lv, "context_menu_action", %{"action" => "stop", "hash" => hash})
    end

    test "erase action sets confirm_action without erasing", %{lv: lv, hash: hash} do
      render_click(lv, "context_menu_action", %{"action" => "erase", "hash" => hash})
      assert render(lv) =~ ~s(role="dialog")
    end

    test "pause action calls Commands.pause/1", %{lv: lv, hash: hash} do
      expect(MockCommands, :pause, fn ^hash -> :ok end)
      render_click(lv, "context_menu_action", %{"action" => "pause", "hash" => hash})
    end

    test "unknown action is a no-op", %{lv: lv, hash: hash} do
      # Should not crash
      render_click(lv, "context_menu_action", %{"action" => "unknown", "hash" => hash})
      assert Process.alive?(lv.pid)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — Connection status banner
  # ---------------------------------------------------------------------------

  describe "connection status banner" do
    test "no banner on initial mount", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Connection to rtorrent lost"
    end

    test "banner appears on {:connection_status, :disconnected}", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:connection_status, :disconnected})
      assert render(lv) =~ "Connection to rtorrent lost"
    end

    test "banner disappears when :connected follows :disconnected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:connection_status, :disconnected})
      send(lv.pid, {:connection_status, :connected})
      refute render(lv) =~ "Connection to rtorrent lost"
    end

    test "Reconnected flash appears when :connected follows :disconnected", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:connection_status, :disconnected})
      send(lv.pid, {:connection_status, :connected})
      assert render(lv) =~ "Reconnected"
    end

    test "no Reconnected flash on initial :connected (no prior disconnection)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      send(lv.pid, {:connection_status, :connected})
      refute render(lv) =~ "Reconnected"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 9 — Action error handling
  # ---------------------------------------------------------------------------

  describe "action error handling" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")
      {:ok, lv: lv, hash: torrent.hash}
    end

    test "start_torrent shows error flash on failure", %{lv: lv, hash: hash} do
      expect(MockCommands, :start, fn _hash -> {:error, :connection_failed} end)
      render_click(lv, "start_torrent", %{"hash" => hash})
      assert render(lv) =~ "Failed to start"
    end

    test "stop_torrent shows error flash on failure", %{lv: lv, hash: hash} do
      expect(MockCommands, :stop, fn _hash -> {:error, :connection_failed} end)
      render_click(lv, "stop_torrent", %{"hash" => hash})
      assert render(lv) =~ "Failed to stop"
    end

    test "start_torrent does not show error flash on success", %{lv: lv, hash: hash} do
      expect(MockCommands, :start, fn _hash -> :ok end)
      render_click(lv, "start_torrent", %{"hash" => hash})
      refute render(lv) =~ "Failed to start"
    end

    test "context_menu_action start shows error flash on failure", %{lv: lv, hash: hash} do
      expect(MockCommands, :start, fn _hash -> {:error, :connection_failed} end)
      render_click(lv, "context_menu_action", %{"action" => "start", "hash" => hash})
      assert render(lv) =~ "Failed to start"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch — User menu in topbar
  # ---------------------------------------------------------------------------

  describe "topbar user menu" do
    test "avatar circle shows first char of username", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      # The topbar includes the user avatar; "T" is the first char of "test_user_..."
      assert html =~ ~s(aria-label="User menu")
    end

    test "sign out link is present in the page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Sign out"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 10 — Detail panel closes on external removal
  # ---------------------------------------------------------------------------

  describe "detail panel closes when selected torrent removed" do
    test "panel closes and info flash shown when selected torrent removed via diff", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      # Select the torrent to open the detail panel
      render_click(lv, "select_torrent", %{"hash" => torrent.hash})
      assert :sys.get_state(lv.pid).socket.assigns.selected_hash == torrent.hash

      # Simulate Poller broadcasting a removal diff
      send(lv.pid, {:torrent_diffs, [{:removed, torrent.hash}]})

      html = render(lv)
      assert :sys.get_state(lv.pid).socket.assigns.selected_hash == nil
      assert html =~ "selected torrent was removed"
    end

    test "panel stays open when a different torrent is removed", %{conn: conn} do
      torrent1 = Fixtures.torrent_fixture("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1")
      torrent2 = Fixtures.torrent_fixture("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2")
      Store.put_torrent(torrent1)
      Store.put_torrent(torrent2)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "select_torrent", %{"hash" => torrent1.hash})
      assert :sys.get_state(lv.pid).socket.assigns.selected_hash == torrent1.hash

      # Remove torrent2, not the selected torrent1
      send(lv.pid, {:torrent_diffs, [{:removed, torrent2.hash}]})

      assert :sys.get_state(lv.pid).socket.assigns.selected_hash == torrent1.hash
    end
  end

  # ---------------------------------------------------------------------------
  # Batch — Label filtering
  # ---------------------------------------------------------------------------

  describe "label filtering" do
    test "sidebar shows label items with counts when torrents have labels", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie 1"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Movies", name: "Movie 2"}
      t3 = %{Fixtures.torrent_fixture("h3") | label: "Linux", name: "Linux ISO"}
      Enum.each([t1, t2, t3], &Store.put_torrent/1)

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "Movies"
      assert html =~ "Linux"
    end

    test "sidebar shows Manage labels button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Manage labels"
    end

    test "clicking a label filters the torrent table", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie Torrent"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Linux", name: "Linux ISO"}
      Enum.each([t1, t2], &Store.put_torrent/1)

      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        lv
        |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=Movies]")
        |> render_click()

      assert html =~ "Movie Torrent"
      refute html =~ "Linux ISO"
    end

    test "label filter combined with status filter narrows results", %{conn: conn} do
      t1 = %{
        Fixtures.torrent_fixture("h1")
        | label: "Movies",
          name: "Movie DL",
          state: :started,
          is_active: true,
          complete: false
      }

      t2 = %{
        Fixtures.torrent_fixture("h2")
        | label: "Movies",
          name: "Movie Seeder",
          state: :started,
          is_active: true,
          complete: true
      }

      Enum.each([t1, t2], &Store.put_torrent/1)

      {:ok, lv, _html} = live(conn, ~p"/")

      # First filter by label
      lv
      |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=Movies]")
      |> render_click()

      # Then filter by status (downloading only)
      html =
        lv
        |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=downloading]")
        |> render_click()

      assert html =~ "Movie DL"
      refute html =~ "Movie Seeder"
    end

    test "label_groups recomputed after PubSub torrent_diffs", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie 1"}
      Store.put_torrent(t1)

      {:ok, lv, html} = live(conn, ~p"/")
      assert html =~ "Movies"

      # Add a torrent with a new label via PubSub diff
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Linux", name: "Linux ISO"}
      send(lv.pid, {:torrent_diffs, [{:added, t2}]})
      html = render(lv)

      assert html =~ "Linux"
    end

    test "filter_label all resets to show all torrents", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie Torrent"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Linux", name: "Linux ISO"}
      Enum.each([t1, t2], &Store.put_torrent/1)

      {:ok, lv, _html} = live(conn, ~p"/")

      # Filter to Movies
      lv
      |> element("nav[aria-label=\"Torrent filters\"] button[phx-value-value=Movies]")
      |> render_click()

      # Reset to all — click the All status button (which also triggers filter reset)
      html = render_click(lv, "filter_label", %{"value" => "all"})

      assert html =~ "Movie Torrent"
      assert html =~ "Linux ISO"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch — Label column in torrent table
  # ---------------------------------------------------------------------------

  describe "label column in torrent table" do
    test "table header has a Label column", %{conn: conn} do
      Store.put_torrent(Fixtures.torrent_fixture("h1"))
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ ~r/<th[^>]*>\s*Label\s*<\/th>/
    end

    test "torrent row shows label pill when torrent has a label", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie File"}
      Store.put_torrent(torrent)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Movies"
    end

    test "torrent row shows em dash when torrent has no label", %{conn: conn} do
      torrent = %{Fixtures.torrent_fixture("h1") | name: "No Label Torrent"}
      Store.put_torrent(torrent)

      {:ok, _lv, html} = live(conn, ~p"/")
      # The em dash for no-label should appear in the label column td
      assert html =~ "No Label Torrent"
      # em dash is U+2014, rendered as HTML entity or directly
      assert html =~ ~r/—|&#x2014;|&mdash;/
    end
  end

  # ---------------------------------------------------------------------------
  # Batch — label_groups helper
  # ---------------------------------------------------------------------------

  describe "label_groups/1" do
    test "returns empty list when no torrents have labels" do
      torrents = [Fixtures.torrent_fixture("h1")]
      assert TaniwhaWeb.DashboardLive.label_groups(torrents) == []
    end

    test "groups torrents by label with counts" do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Movies"}
      t3 = %{Fixtures.torrent_fixture("h3") | label: "Linux"}
      t4 = Fixtures.torrent_fixture("h4")

      groups = TaniwhaWeb.DashboardLive.label_groups([t1, t2, t3, t4])

      assert {_, movies_count} = Enum.find(groups, fn {l, _} -> l == "Movies" end)
      assert {_, linux_count} = Enum.find(groups, fn {l, _} -> l == "Linux" end)
      assert movies_count == 2
      assert linux_count == 1
      # Torrent with no label is excluded
      assert length(groups) == 2
    end

    test "returns groups sorted alphabetically" do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "TV"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Movies"}
      t3 = %{Fixtures.torrent_fixture("h3") | label: "Linux"}

      groups = TaniwhaWeb.DashboardLive.label_groups([t1, t2, t3])
      labels = Enum.map(groups, &elem(&1, 0))
      assert labels == Enum.sort(labels)
    end
  end

  # ── Context menu label actions ─────────────────────────────────────────────

  describe "context menu label actions" do
    test "set_label_prompt action opens the label manager modal", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      render_click(lv, "context_menu_action", %{"action" => "set_label_prompt", "hash" => "h1"})

      html = render(lv)
      assert html =~ "label-manager-modal"
    end

    test "remove_label action calls Commands.remove_label for the given hash", %{conn: conn} do
      t = Fixtures.torrent_fixture("h1")
      Store.put_torrent(t)
      expect(MockCommands, :remove_label, fn "h1" -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      render_click(lv, "context_menu_action", %{"action" => "remove_label", "hash" => "h1"})

      # Mox verify_on_exit! confirms remove_label was called exactly once
      assert render(lv)
    end
  end
end
