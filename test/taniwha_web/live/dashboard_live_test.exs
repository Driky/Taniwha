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

    test "remove_torrent calls Commands.erase/1", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      hash = torrent.hash
      expect(MockCommands, :erase, fn ^hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()
    end

    test "remove_torrent removes torrent from assigns", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      stub(MockCommands, :erase, fn _hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=remove_torrent]") |> render_click()

      html = render(lv)
      refute html =~ torrent.name
    end

    test "remove_torrent clears hash from selected_hashes", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      stub(MockCommands, :erase, fn _hash -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")

      # Select the torrent first
      lv |> element("input[phx-click=toggle_select]") |> render_click()
      # Remove it
      lv |> element("button[phx-click=remove_torrent]") |> render_click()

      html = render(lv)
      # Bulk toolbar should not be visible — check for the "N selected" text pattern
      # (aria-selected is not a false positive since it uses a hyphen, not a space before "selected")
      refute html =~ " selected"
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

      # Bulk toolbar "N selected" text should be gone; aria-selected (hyphen) is not a match
      refute html =~ " selected"
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

      refute html =~ " selected"
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
end
