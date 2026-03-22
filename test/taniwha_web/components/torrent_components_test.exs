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

    test "applies blue (info) color class" do
      html = render_component(&progress_bar/1, value: 50.0, color: :blue)
      assert html =~ "bg-info"
    end

    test "applies green (success) color class" do
      html = render_component(&progress_bar/1, value: 50.0, color: :green)
      assert html =~ "bg-success"
    end

    test "applies gray (neutral) color class" do
      html = render_component(&progress_bar/1, value: 50.0, color: :gray)
      assert html =~ "bg-neutral"
    end

    test "applies yellow (warning) color class" do
      html = render_component(&progress_bar/1, value: 50.0, color: :yellow)
      assert html =~ "bg-warning"
    end

    test "default color renders" do
      html = render_component(&progress_bar/1, value: 50.0)
      assert html =~ "bg-"
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
    test "renders downloading with badge-info" do
      html = render_component(&status_badge/1, status: :downloading)
      assert html =~ "badge-info"
      assert html =~ "Downloading"
    end

    test "renders seeding with badge-success" do
      html = render_component(&status_badge/1, status: :seeding)
      assert html =~ "badge-success"
      assert html =~ "Seeding"
    end

    test "renders stopped with badge-neutral" do
      html = render_component(&status_badge/1, status: :stopped)
      assert html =~ "badge-neutral"
      assert html =~ "Stopped"
    end

    test "renders paused with badge-warning" do
      html = render_component(&status_badge/1, status: :paused)
      assert html =~ "badge-warning"
      assert html =~ "Paused"
    end

    test "renders checking with badge-primary" do
      html = render_component(&status_badge/1, status: :checking)
      assert html =~ "badge-primary"
      assert html =~ "Checking"
    end

    test "renders unknown with badge-ghost" do
      html = render_component(&status_badge/1, status: :unknown)
      assert html =~ "badge-ghost"
      assert html =~ "Unknown"
    end

    test "renders a span element" do
      html = render_component(&status_badge/1, status: :stopped)
      assert html =~ "<span"
      assert html =~ "badge"
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
  end

  # ---------------------------------------------------------------------------
  # global_stats_bar/1
  # ---------------------------------------------------------------------------

  describe "global_stats_bar/1" do
    test "has role=status" do
      html = render_component(&global_stats_bar/1, [])
      assert html =~ ~s(role="status")
    end

    test "has aria-label for global statistics" do
      html = render_component(&global_stats_bar/1, [])
      assert html =~ "Global transfer statistics"
    end

    test "shows upload rate" do
      html = render_component(&global_stats_bar/1, upload_rate: 2_048)
      assert html =~ "KB/s"
    end

    test "shows download rate" do
      html = render_component(&global_stats_bar/1, download_rate: 1_024)
      assert html =~ "KB/s"
    end

    test "shows active and total count" do
      html = render_component(&global_stats_bar/1, active_count: 3, total_count: 10)
      assert html =~ "3"
      assert html =~ "10"
    end

    test "defaults to zeros when no assigns given" do
      html = render_component(&global_stats_bar/1, [])
      assert html =~ "0 B/s"
    end
  end

  # ---------------------------------------------------------------------------
  # torrent_row/1
  # ---------------------------------------------------------------------------

  describe "torrent_row/1" do
    test "renders torrent name" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ torrent.name
    end

    test "renders progress bar" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(role="progressbar")
    end

    test "renders status badge" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "badge"
    end

    test "name span has title attribute for truncation tooltip" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(title="#{torrent.name}")
    end

    test "remove button has descriptive aria-label" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ ~s(aria-label="Remove #{torrent.name}")
    end

    test "all buttons have accessible labels" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert_labeled_buttons(html)
    end

    test "renders download speed" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "hero-arrow-down-micro"
    end

    test "renders upload speed" do
      torrent = Fixtures.torrent_fixture()
      html = render_component(&torrent_row/1, torrent: torrent)
      assert html =~ "hero-arrow-up-micro"
    end
  end
end
