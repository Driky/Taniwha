defmodule TaniwhaWeb.DetailPanelTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Taniwha.{MockCommands, Peer, State.Store, Tracker, TorrentFile}
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
  # Batch 1 — Panel visibility
  # ---------------------------------------------------------------------------

  describe "panel visibility" do
    test "panel content is hidden when no torrent is selected", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, _lv, html} = live(conn, ~p"/")
      # Panel has aria-label but no torrent name in the panel section
      refute html =~ ~r/role="region" [^>]*aria-label="Torrent details"[^>]*>[^<]*#{torrent.name}/
    end

    test "update_selection opens the panel with that torrent's data", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      html =
        render_click(lv, "update_selection", %{
          "hashes" => [torrent.hash],
          "focused_hash" => torrent.hash
        })

      assert html =~ "Torrent details"
      assert html =~ torrent.name
    end

    test "update_selection with same focused_hash keeps panel open", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      # Selecting same row again does not close the panel
      html =
        render_click(lv, "update_selection", %{
          "hashes" => [torrent.hash],
          "focused_hash" => torrent.hash
        })

      refute html =~ ~r/id="detail-panel"[^>]*class="[^"]*max-h-0/
    end

    test "update_selection with different focused_hash switches panel content", %{conn: conn} do
      torrent_a = Fixtures.torrent_fixture("hash_a")
      torrent_b = Fixtures.torrent_fixture("hash_b") |> Map.put(:name, "Torrent B")
      Store.put_torrent(torrent_a)
      Store.put_torrent(torrent_b)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => ["hash_a"],
        "focused_hash" => "hash_a"
      })

      html =
        render_click(lv, "update_selection", %{
          "hashes" => ["hash_b"],
          "focused_hash" => "hash_b"
        })

      # Panel stays open and shows torrent B's name
      assert html =~ "Torrent B"
      # Panel is still visible (not max-h-0)
      refute html =~ ~r/id="detail-panel"[^>]*class="[^"]*max-h-0/
    end

    test "close button closes the panel", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      html =
        lv
        |> element("button[phx-click='close_panel']")
        |> render_click()

      assert html =~ ~r/id="detail-panel"[^>]*class="[^"]*max-h-0/
    end

    test "Escape key closes the panel", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      html = render_keydown(lv, "keydown", %{"key" => "Escape"})

      assert html =~ ~r/id="detail-panel"[^>]*class="[^"]*max-h-0/
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — Tab switching
  # ---------------------------------------------------------------------------

  describe "tab switching" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      {:ok, lv: lv, torrent: torrent}
    end

    test "General tab is active by default when panel opens", %{lv: lv} do
      html = render(lv)
      # General tab button has aria-selected="true"
      assert html =~ ~r/id="panel-tab-general"[^>]*aria-selected="true"/
    end

    test "clicking Files tab switches active tab", %{lv: lv} do
      stub(MockCommands, :list_files, fn _hash -> {:ok, []} end)

      html =
        lv
        |> element("button[role='tab'][phx-value-tab='files']")
        |> render_click()

      assert html =~ ~r/id="panel-tab-files"[^>]*aria-selected="true"/
    end

    test "clicking Peers tab switches active tab", %{lv: lv} do
      stub(MockCommands, :list_peers, fn _hash -> {:ok, []} end)

      html =
        lv
        |> element("button[role='tab'][phx-value-tab='peers']")
        |> render_click()

      assert html =~ ~r/id="panel-tab-peers"[^>]*aria-selected="true"/
    end

    test "clicking Trackers tab switches active tab", %{lv: lv} do
      stub(MockCommands, :list_trackers, fn _hash -> {:ok, []} end)

      html =
        lv
        |> element("button[role='tab'][phx-value-tab='trackers']")
        |> render_click()

      assert html =~ ~r/id="panel-tab-trackers"[^>]*aria-selected="true"/
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — General tab content
  # ---------------------------------------------------------------------------

  describe "general_tab" do
    test "renders key field labels", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      html = render(lv)
      assert html =~ "Name"
      assert html =~ "Save path"
      assert html =~ "Size"
      assert html =~ "Hash"
      assert html =~ "Ratio"
    end

    test "renders the torrent name in the general tab", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      html = render(lv)
      assert html =~ torrent.name
    end

    test "renders hash in monospace style", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      html = render(lv)
      assert html =~ "font-mono"
      assert html =~ torrent.hash
    end

    test "renders — for nil finished_at", %{conn: conn} do
      torrent = Fixtures.torrent_fixture() |> Map.put(:finished_at, nil)
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      html = render(lv)
      # finished_at renders as "—" when nil
      assert html =~ "—"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — Files tab
  # ---------------------------------------------------------------------------

  describe "files_tab" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      {:ok, lv: lv, torrent: torrent}
    end

    test "shows loading state after switching to files tab", %{lv: lv} do
      stub(MockCommands, :list_files, fn _hash ->
        Process.sleep(100)
        {:ok, []}
      end)

      html =
        lv
        |> element("button[role='tab'][phx-value-tab='files']")
        |> render_click()

      # Shows loading skeleton immediately
      assert html =~ "animate-pulse"
    end

    test "renders file list after async load", %{lv: lv} do
      file = %TorrentFile{
        path: "video/movie.mkv",
        size: 700_000_000,
        priority: 1,
        completed_chunks: 5000,
        total_chunks: 10_000
      }

      stub(MockCommands, :list_files, fn _hash -> {:ok, [file]} end)

      lv
      |> element("button[role='tab'][phx-value-tab='files']")
      |> render_click()

      html = render(lv)
      assert html =~ "movie.mkv"
    end

    test "shows error message when list_files fails", %{lv: lv} do
      stub(MockCommands, :list_files, fn _hash -> {:error, :timeout} end)

      lv
      |> element("button[role='tab'][phx-value-tab='files']")
      |> render_click()

      html = render(lv)
      assert html =~ "Failed to load files"
    end

    test "priority change triggers set_file_priority command", %{lv: lv, torrent: torrent} do
      file = %TorrentFile{
        path: "file.mkv",
        size: 100,
        priority: 1,
        completed_chunks: 0,
        total_chunks: 1
      }

      stub(MockCommands, :list_files, fn _hash -> {:ok, [file]} end)

      lv
      |> element("button[role='tab'][phx-value-tab='files']")
      |> render_click()

      _html = render(lv)

      hash = torrent.hash
      expect(MockCommands, :set_file_priority, fn ^hash, 0, 0 -> :ok end)

      render_click(lv, "set_file_priority", %{"hash" => hash, "index" => "0", "priority" => "0"})
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 5 — Peers tab
  # ---------------------------------------------------------------------------

  describe "peers_tab" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      {:ok, lv: lv, torrent: torrent}
    end

    test "shows loading state after switching to peers tab", %{lv: lv} do
      stub(MockCommands, :list_peers, fn _hash ->
        Process.sleep(100)
        {:ok, []}
      end)

      html =
        lv
        |> element("button[role='tab'][phx-value-tab='peers']")
        |> render_click()

      assert html =~ "animate-pulse"
    end

    test "renders peer list with IP:Port in monospace", %{lv: lv} do
      peer = %Peer{
        address: "192.168.1.1",
        port: 51_413,
        client_version: "uTorrent/3.5.5",
        down_rate: 512_000,
        up_rate: 0,
        completed_percent: 75.0
      }

      stub(MockCommands, :list_peers, fn _hash -> {:ok, [peer]} end)

      lv
      |> element("button[role='tab'][phx-value-tab='peers']")
      |> render_click()

      html = render(lv)
      assert html =~ "192.168.1.1:51413"
      assert html =~ "font-mono"
      assert html =~ "192.168.1.1:51413"
    end

    test "shows empty state when no peers", %{lv: lv} do
      stub(MockCommands, :list_peers, fn _hash -> {:ok, []} end)

      lv
      |> element("button[role='tab'][phx-value-tab='peers']")
      |> render_click()

      html = render(lv)
      assert html =~ "No peers connected"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6 — Trackers tab
  # ---------------------------------------------------------------------------

  describe "trackers_tab" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      {:ok, lv: lv, torrent: torrent}
    end

    test "shows loading state after switching to trackers tab", %{lv: lv} do
      stub(MockCommands, :list_trackers, fn _hash ->
        Process.sleep(100)
        {:ok, []}
      end)

      html =
        lv
        |> element("button[role='tab'][phx-value-tab='trackers']")
        |> render_click()

      assert html =~ "animate-pulse"
    end

    test "renders tracker list with URL", %{lv: lv} do
      tracker = %Tracker{
        url: "http://tracker.example.com/announce",
        is_enabled: true,
        scrape_complete: 42,
        scrape_incomplete: 5,
        normal_interval: 1800
      }

      stub(MockCommands, :list_trackers, fn _hash -> {:ok, [tracker]} end)

      lv
      |> element("button[role='tab'][phx-value-tab='trackers']")
      |> render_click()

      html = render(lv)
      assert html =~ "tracker.example.com"
    end

    test "shows empty state when no trackers", %{lv: lv} do
      stub(MockCommands, :list_trackers, fn _hash -> {:ok, []} end)

      lv
      |> element("button[role='tab'][phx-value-tab='trackers']")
      |> render_click()

      html = render(lv)
      assert html =~ "No trackers"
    end

    test "enabled tracker has green status indicator", %{lv: lv} do
      tracker = %Tracker{
        url: "http://t.example.com/announce",
        is_enabled: true,
        scrape_complete: 0,
        scrape_incomplete: 0,
        normal_interval: 0
      }

      stub(MockCommands, :list_trackers, fn _hash -> {:ok, [tracker]} end)

      lv
      |> element("button[role='tab'][phx-value-tab='trackers']")
      |> render_click()

      html = render(lv)
      assert html =~ ~r/text-green/
    end

    test "disabled tracker has gray status indicator", %{lv: lv} do
      tracker = %Tracker{
        url: "http://t.example.com/announce",
        is_enabled: false,
        scrape_complete: 0,
        scrape_incomplete: 0,
        normal_interval: 0
      }

      stub(MockCommands, :list_trackers, fn _hash -> {:ok, [tracker]} end)

      lv
      |> element("button[role='tab'][phx-value-tab='trackers']")
      |> render_click()

      html = render(lv)
      assert html =~ ~r/text-gray/
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 7 — PubSub lifecycle
  # ---------------------------------------------------------------------------

  describe "PubSub lifecycle" do
    test "handle_info({:torrent_updated}) refreshes panel data", %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      updated = %{torrent | name: "Updated Torrent Name", download_rate: 9_999_999}
      send(lv.pid, {:torrent_updated, updated})

      html = render(lv)
      assert html =~ "Updated Torrent Name"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — Accessibility
  # ---------------------------------------------------------------------------

  describe "accessibility" do
    setup %{conn: conn} do
      torrent = Fixtures.torrent_fixture()
      Store.put_torrent(torrent)
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "update_selection", %{
        "hashes" => [torrent.hash],
        "focused_hash" => torrent.hash
      })

      {:ok, lv: lv}
    end

    test "panel has role=region and aria-label", %{lv: lv} do
      html = render(lv)
      assert html =~ ~s(id="detail-panel")
      assert html =~ ~s(role="region")
      assert html =~ ~s(aria-label="Torrent details")
    end

    test "tab bar has role=tablist", %{lv: lv} do
      html = render(lv)
      assert html =~ ~s(role="tablist")
    end

    test "active tab has aria-selected=true, others have aria-selected=false", %{lv: lv} do
      html = render(lv)
      assert html =~ ~s(aria-selected="true")
      assert html =~ ~s(aria-selected="false")
    end

    test "tab panel has role=tabpanel", %{lv: lv} do
      html = render(lv)
      assert html =~ ~s(role="tabpanel")
    end
  end
end
