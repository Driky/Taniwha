defmodule TaniwhaWeb.TorrentComponentsTest do
  use TaniwhaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TaniwhaWeb.TorrentComponents
  import TaniwhaWeb.AccessibilityHelper

  alias Taniwha.Test.Fixtures

  # ---------------------------------------------------------------------------
  # progress_bar/1
  # ---------------------------------------------------------------------------

  describe "progress_bar/1" do
    test "renders role=progressbar with aria attributes" do
      html = render_component(&progress_bar/1, value: 50.0)
      assert_aria_progressbar(html)
    end

    test "aria-valuenow is rounded value" do
      html = render_component(&progress_bar/1, value: 33.7)
      assert html =~ ~s(aria-valuenow="34")
    end

    test "aria-valuemin=0 and aria-valuemax=100" do
      html = render_component(&progress_bar/1, value: 0.0)
      assert html =~ ~s(aria-valuemin="0")
      assert html =~ ~s(aria-valuemax="100")
    end

    test "inner bar is 3px height" do
      html = render_component(&progress_bar/1, value: 50.0)
      assert html =~ "h-[3px]"
    end

    test "inner bar uses CSS variable for downloading color" do
      html = render_component(&progress_bar/1, value: 50.0, color: :downloading)
      assert html =~ "taniwha-status-dl-bar"
    end

    test "inner bar uses CSS variable for seeding color" do
      html = render_component(&progress_bar/1, value: 100.0, color: :seeding)
      assert html =~ "taniwha-status-seed-bar"
    end

    test "inner bar uses CSS variable for stopped color" do
      html = render_component(&progress_bar/1, value: 0.0, color: :stopped)
      assert html =~ "taniwha-status-stop-bar"
    end

    test "default color renders a CSS var style" do
      html = render_component(&progress_bar/1, value: 50.0)
      assert html =~ "var(--taniwha-"
    end

    test "has transition-all class for smooth animation" do
      html = render_component(&progress_bar/1, value: 50.0)
      assert html =~ "transition-all"
    end

    test "renders with id attribute when provided" do
      html = render_component(&progress_bar/1, value: 25.0, id: "my-bar")
      assert html =~ ~s(id="my-bar")
    end

    test "width style reflects the value" do
      html = render_component(&progress_bar/1, value: 75.0)
      assert html =~ "width: 75.0%"
    end
  end

  # ---------------------------------------------------------------------------
  # status_badge/1
  # ---------------------------------------------------------------------------

  describe "status_badge/1" do
    test "renders a span element" do
      html = render_component(&status_badge/1, status: :stopped)
      assert html =~ "<span"
    end

    test "renders abbreviated label DL for downloading" do
      html = render_component(&status_badge/1, status: :downloading)
      assert html =~ "DL"
    end

    test "renders abbreviated label Seed for seeding" do
      html = render_component(&status_badge/1, status: :seeding)
      assert html =~ "Seed"
    end

    test "renders abbreviated label Stop for stopped" do
      html = render_component(&status_badge/1, status: :stopped)
      assert html =~ "Stop"
    end

    test "renders abbreviated label Pause for paused" do
      html = render_component(&status_badge/1, status: :paused)
      assert html =~ "Pause"
    end

    test "renders abbreviated label Check for checking" do
      html = render_component(&status_badge/1, status: :checking)
      assert html =~ "Check"
    end

    test "renders label for unknown status" do
      html = render_component(&status_badge/1, status: :unknown)
      assert html =~ "Unknown"
    end

    test "badge uses CSS variable for background color" do
      html = render_component(&status_badge/1, status: :downloading)
      assert html =~ "taniwha-status-dl-badge-bg"
    end

    test "includes a coloured status dot for seeding" do
      html = render_component(&status_badge/1, status: :seeding)
      assert html =~ "taniwha-status-seed-dot"
    end
  end

  # ---------------------------------------------------------------------------
  # speed_display/1
  # ---------------------------------------------------------------------------

  describe "speed_display/1" do
    test "formats bytes below 1 KB as B/s" do
      html = render_component(&speed_display/1, bytes_per_second: 512)
      assert html =~ "512 B/s"
    end

    test "formats bytes below 1 MB as KB/s with 1 decimal" do
      html = render_component(&speed_display/1, bytes_per_second: 2_048)
      assert html =~ "2.0 KB/s"
    end

    test "formats bytes below 1 GB as MB/s with 2 decimals" do
      html = render_component(&speed_display/1, bytes_per_second: 1_572_864)
      assert html =~ "1.50 MB/s"
    end

    test "formats bytes >= 1 GB as GB/s with 2 decimals" do
      html = render_component(&speed_display/1, bytes_per_second: 2_147_483_648)
      assert html =~ "2.00 GB/s"
    end

    test "renders upload arrow icon for direction :up" do
      html = render_component(&speed_display/1, bytes_per_second: 1_024, direction: :up)
      assert html =~ "hero-arrow-up-micro"
    end

    test "renders download arrow icon for direction :down" do
      html = render_component(&speed_display/1, bytes_per_second: 1_024, direction: :down)
      assert html =~ "hero-arrow-down-micro"
    end

    test "renders no directional icon when direction is nil" do
      html = render_component(&speed_display/1, bytes_per_second: 1_024)
      refute html =~ "hero-arrow-up-micro"
      refute html =~ "hero-arrow-down-micro"
    end

    test "zero bytes renders as 0 B/s" do
      html = render_component(&speed_display/1, bytes_per_second: 0)
      assert html =~ "0 B/s"
    end

    test "download direction uses --taniwha-speed-dl color" do
      html = render_component(&speed_display/1, bytes_per_second: 1_024, direction: :down)
      assert html =~ "taniwha-speed-dl"
    end

    test "upload direction uses --taniwha-speed-ul color" do
      html = render_component(&speed_display/1, bytes_per_second: 1_024, direction: :up)
      assert html =~ "taniwha-speed-ul"
    end
  end

  # ---------------------------------------------------------------------------
  # sidebar/1
  # ---------------------------------------------------------------------------

  describe "sidebar/1" do
    defp base_counts,
      do: %{all: 6, downloading: 2, seeding: 2, stopped: 1, checking: 1, paused: 0}

    test "renders a nav element with aria-label" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ "<nav"
      assert html =~ ~s(aria-label="Torrent filters")
    end

    test "renders Status section header" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ "Status"
    end

    test "renders all five status filter items" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ "All"
      assert html =~ "Downloading"
      assert html =~ "Seeding"
      assert html =~ "Stopped"
      assert html =~ "Checking"
    end

    test "active filter item has aria-pressed=true" do
      html =
        render_component(&sidebar/1,
          filter: :downloading,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ ~s(aria-pressed="true")
    end

    test "inactive filter items have aria-pressed=false" do
      html =
        render_component(&sidebar/1,
          filter: :downloading,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ ~s(aria-pressed="false")
    end

    test "count badges show correct numbers" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      # The all-count badge shows 6 and the downloading/seeding badges show 2
      assert html =~ ~r/leading-\[17px\][^>]*>\s*6\s*</
      assert html =~ ~r/leading-\[17px\][^>]*>\s*2\s*</
    end

    test "renders Trackers section header" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ "Trackers"
    end

    test "renders tracker groups dynamically" do
      groups = [{"releases.ubuntu.com", 2}, {"archlinux.org", 1}]

      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts(),
          tracker_groups: groups
        )

      assert html =~ "releases.ubuntu.com"
      assert html =~ "archlinux.org"
    end

    test "renders Labels section header" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ "Labels"
    end

    test "shows empty labels placeholder text" do
      html =
        render_component(&sidebar/1,
          filter: :all,
          tracker_filter: :all,
          status_counts: base_counts()
        )

      assert html =~ "No labels yet"
    end
  end

  # ---------------------------------------------------------------------------
  # topbar/1
  # ---------------------------------------------------------------------------

  describe "topbar/1" do
    test "renders the logo text Taniwha" do
      html = render_component(&topbar/1, [])
      assert html =~ "Taniwha"
    end

    test "search input is wrapped in a search element" do
      html = render_component(&topbar/1, [])
      assert html =~ "<search"
    end

    test "search input has a label" do
      html = render_component(&topbar/1, [])
      assert html =~ "<label"
    end

    test "search input has phx-change=search" do
      html = render_component(&topbar/1, [])
      assert html =~ ~s(phx-change="search")
    end

    test "search input has phx-debounce" do
      html = render_component(&topbar/1, [])
      assert html =~ "phx-debounce"
    end

    test "renders download speed with arrow-down icon" do
      html = render_component(&topbar/1, download_rate: 1_572_864)
      assert html =~ "hero-arrow-down-micro"
      assert html =~ "MB/s"
    end

    test "renders upload speed with arrow-up icon" do
      html = render_component(&topbar/1, upload_rate: 1_024)
      assert html =~ "hero-arrow-up-micro"
    end

    test "renders Add torrent button" do
      html = render_component(&topbar/1, [])
      assert html =~ "Add"
    end

    test "stats region has role=status" do
      html = render_component(&topbar/1, [])
      assert html =~ ~s(role="status")
    end
  end

  # ---------------------------------------------------------------------------
  # action_bar/1
  # ---------------------------------------------------------------------------

  describe "action_bar/1" do
    test "renders visible torrent count" do
      html = render_component(&action_bar/1, visible_count: 6)
      assert html =~ "6"
    end

    test "renders Start bulk action button" do
      html = render_component(&action_bar/1, visible_count: 3)
      assert html =~ ~s(phx-click="bulk_start")
    end

    test "renders Stop bulk action button" do
      html = render_component(&action_bar/1, visible_count: 3)
      assert html =~ ~s(phx-click="bulk_stop")
    end

    test "all buttons have accessible labels" do
      html = render_component(&action_bar/1, visible_count: 3)
      assert_labeled_buttons(html)
    end

    test "deselect button appears when selected_count > 0" do
      html = render_component(&action_bar/1, visible_count: 3, selected_count: 2)
      assert html =~ ~s(phx-click="deselect_all")
    end

    test "shows N selected text when selected_count > 0" do
      html = render_component(&action_bar/1, visible_count: 3, selected_count: 2)
      assert html =~ "2 selected"
    end

    test "does not show selected text when selected_count is 0" do
      html = render_component(&action_bar/1, visible_count: 3, selected_count: 0)
      refute html =~ " selected"
    end
  end

  # ---------------------------------------------------------------------------
  # table_header/1
  # ---------------------------------------------------------------------------

  describe "table_header/1" do
    defp base_header_assigns do
      [sort_by: :name, sort_dir: :asc, all_selected?: false, total_visible: 5]
    end

    test "renders all nine column names" do
      html = render_component(&table_header/1, base_header_assigns())
      assert html =~ "Name"
      assert html =~ "Size"
      assert html =~ "Progress"
      assert html =~ "Down"
      assert html =~ "Up"
      assert html =~ "Seeds"
      assert html =~ "Peers"
      assert html =~ "Ratio"
      assert html =~ "Status"
    end

    test "active sort column has aria-sort=ascending" do
      html = render_component(&table_header/1, base_header_assigns())
      assert html =~ ~s(aria-sort="ascending")
    end

    test "descending sort produces aria-sort=descending" do
      html =
        render_component(&table_header/1,
          sort_by: :name,
          sort_dir: :desc,
          all_selected?: false,
          total_visible: 5
        )

      assert html =~ ~s(aria-sort="descending")
    end

    test "sortable columns have phx-click=sort" do
      html = render_component(&table_header/1, base_header_assigns())
      assert html =~ ~s(phx-click="sort")
    end

    test "select-all checkbox is rendered" do
      html = render_component(&table_header/1, base_header_assigns())
      assert html =~ ~s(type="checkbox")
    end
  end

  # ---------------------------------------------------------------------------
  # torrent_row/1
  # ---------------------------------------------------------------------------

  describe "torrent_row/1" do
    test "renders a tr element" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "<tr"
    end

    test "renders torrent name" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ torrent.name
    end

    test "name cell has title attribute for truncation tooltip" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(title="#{torrent.name}")
    end

    test "renders progress bar" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(role="progressbar")
    end

    test "renders status badge with abbreviated label" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      # downloading torrent fixture → "DL"
      assert html =~ "DL"
    end

    test "Seeds column renders em-dash placeholder" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "—"
    end

    test "Peers column renders peers_connected value" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ Integer.to_string(torrent.peers_connected)
    end

    test "renders download speed icon" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "hero-arrow-down-micro"
    end

    test "renders upload speed icon" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "hero-arrow-up-micro"
    end

    test "checkbox has phx-click=toggle_select" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(phx-click="toggle_select")
    end

    test "row has aria-label with torrent name" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(aria-label="#{torrent.name}")
    end

    test "remove button has descriptive aria-label" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(aria-label="Remove #{torrent.name}")
    end

    test "tr has stable id attribute based on hash" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(id="torrent-#{torrent.hash}")
    end

    test "tr has phx-click=select_torrent" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(phx-click="select_torrent")
    end

    test "row_selected? false gives no selected highlight" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent, row_selected?: false)
      refute html =~ "--taniwha-sidebar-active-bg"
    end

    test "row_selected? true applies selected background style" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent, row_selected?: true)
      assert html =~ "--taniwha-sidebar-active-bg"
    end
  end

  # ---------------------------------------------------------------------------
  # torrent_table/1
  # ---------------------------------------------------------------------------

  describe "torrent_table/1" do
    defp table_assigns(torrents, opts \\ []) do
      [
        torrents: torrents,
        all_torrents_empty?: torrents == [] and Keyword.get(opts, :system_empty?, true),
        sort_by: :name,
        sort_dir: :asc,
        selected_hashes: MapSet.new(),
        total_visible: length(torrents),
        selected_hash: nil
      ]
    end

    test "renders a table element" do
      html = render_component(&torrent_table/1, table_assigns([]))
      assert html =~ "<table"
    end

    test "renders thead and tbody" do
      html = render_component(&torrent_table/1, table_assigns([]))
      assert html =~ "<thead"
      assert html =~ "<tbody"
    end

    test "renders correct number of rows when torrents present" do
      t1 = Fixtures.torrent_fixture("h1")
      t2 = %{Fixtures.torrent_fixture("h2") | name: "Second"}
      html = render_component(&torrent_table/1, table_assigns([t1, t2], system_empty?: false))
      # Two torrent rows by hash id
      assert html =~ ~s(id="torrent-h1")
      assert html =~ ~s(id="torrent-h2")
    end

    test "renders no-torrents empty state when system has no torrents" do
      html = render_component(&torrent_table/1, table_assigns([]))
      assert html =~ "No torrents yet"
    end

    test "renders no-results empty state when filtered list is empty but system is not" do
      html =
        render_component(&torrent_table/1,
          torrents: [],
          all_torrents_empty?: false,
          sort_by: :name,
          sort_dir: :asc,
          selected_hashes: MapSet.new(),
          total_visible: 0,
          selected_hash: nil
        )

      assert html =~ "No torrents match"
    end

    test "does not show empty state when torrents are present" do
      t = Fixtures.torrent_fixture()
      html = render_component(&torrent_table/1, table_assigns([t], system_empty?: false))
      refute html =~ "No torrents yet"
      refute html =~ "No torrents match"
    end

    test "passes sort column to table header" do
      html =
        render_component(&torrent_table/1,
          torrents: [],
          all_torrents_empty?: true,
          sort_by: :size,
          sort_dir: :desc,
          selected_hashes: MapSet.new(),
          total_visible: 0,
          selected_hash: nil
        )

      assert html =~ ~s(aria-sort="descending")
    end

    test "selected row has highlighted background" do
      t = Fixtures.torrent_fixture()

      html =
        render_component(&torrent_table/1,
          torrents: [t],
          all_torrents_empty?: false,
          sort_by: :name,
          sort_dir: :asc,
          selected_hashes: MapSet.new(),
          total_visible: 1,
          selected_hash: t.hash
        )

      assert html =~ "--taniwha-sidebar-active-bg"
    end

    test "all_torrents_empty? false + empty visible → no-results state" do
      html =
        render_component(&torrent_table/1,
          torrents: [],
          all_torrents_empty?: false,
          sort_by: :name,
          sort_dir: :asc,
          selected_hashes: MapSet.new(),
          total_visible: 0,
          selected_hash: nil
        )

      assert html =~ "No torrents match"
      refute html =~ "No torrents yet"
    end
  end
end
