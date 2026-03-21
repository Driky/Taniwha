defmodule Taniwha.State.PollerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mox

  alias Taniwha.State.{Poller, Store}
  alias Taniwha.Torrent

  setup :verify_on_exit!

  setup do
    Store.clear()
    :ok
  end

  defp build_torrent(hash, overrides \\ []) do
    struct!(Torrent, Keyword.merge([hash: hash, name: "Torrent #{hash}"], overrides))
  end

  defp start_poller(interval \\ 60_000) do
    {:ok, pid} = GenServer.start_link(Poller, poll_interval: interval)
    Mox.allow(Taniwha.MockCommands, self(), pid)
    pid
  end

  defp poll_and_wait(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
    :ok
  end

  # ── Batch 1: compute_diffs/2 basic cases ─────────────────────────────────

  describe "compute_diffs/2 basic cases" do
    test "empty old + non-empty new → all :added" do
      t1 = build_torrent("hash1")
      t2 = build_torrent("hash2")
      new_map = %{"hash1" => t1, "hash2" => t2}

      diffs = Poller.compute_diffs(%{}, new_map)

      assert length(diffs) == 2
      assert Enum.all?(diffs, fn {type, _} -> type == :added end)
      hashes = Enum.map(diffs, fn {:added, t} -> t.hash end) |> Enum.sort()
      assert hashes == ["hash1", "hash2"]
    end

    test "non-empty old + empty new → all :removed" do
      t1 = build_torrent("hash1")
      t2 = build_torrent("hash2")
      old_map = %{"hash1" => t1, "hash2" => t2}

      diffs = Poller.compute_diffs(old_map, %{})

      assert length(diffs) == 2
      assert Enum.all?(diffs, fn {type, _} -> type == :removed end)
      hashes = Enum.map(diffs, fn {:removed, h} -> h end) |> Enum.sort()
      assert hashes == ["hash1", "hash2"]
    end

    test "identical maps → empty diff list" do
      t1 = build_torrent("hash1")
      map = %{"hash1" => t1}

      assert Poller.compute_diffs(map, map) == []
    end

    test "changed diff field (upload_rate) → one :updated entry" do
      old = build_torrent("hash1", upload_rate: 0)
      new = build_torrent("hash1", upload_rate: 500)
      old_map = %{"hash1" => old}
      new_map = %{"hash1" => new}

      diffs = Poller.compute_diffs(old_map, new_map)

      assert diffs == [{:updated, new}]
    end

    test "changed non-diff field only (name) → empty diff list" do
      old = build_torrent("hash1", name: "Old Name")
      new = build_torrent("hash1", name: "New Name")
      old_map = %{"hash1" => old}
      new_map = %{"hash1" => new}

      assert Poller.compute_diffs(old_map, new_map) == []
    end
  end

  # ── Batch 2: compute_diffs/2 edge cases ──────────────────────────────────

  describe "compute_diffs/2 edge cases" do
    test "multiple torrents with multiple changed diff fields across different torrents" do
      t1_old = build_torrent("h1", upload_rate: 0, download_rate: 0)
      t2_old = build_torrent("h2", upload_rate: 100, peers_connected: 3)
      t1_new = build_torrent("h1", upload_rate: 50, download_rate: 200)
      t2_new = build_torrent("h2", upload_rate: 100, peers_connected: 5)

      old_map = %{"h1" => t1_old, "h2" => t2_old}
      new_map = %{"h1" => t1_new, "h2" => t2_new}

      diffs = Poller.compute_diffs(old_map, new_map)

      assert length(diffs) == 2
      assert {:updated, t1_new} in diffs
      assert {:updated, t2_new} in diffs
    end

    test "mixed: some added, some removed, some updated" do
      existing_old = build_torrent("keep", upload_rate: 0)
      existing_new = build_torrent("keep", upload_rate: 100)
      to_remove = build_torrent("remove_me")
      to_add = build_torrent("new_one")

      old_map = %{"keep" => existing_old, "remove_me" => to_remove}
      new_map = %{"keep" => existing_new, "new_one" => to_add}

      diffs = Poller.compute_diffs(old_map, new_map)

      assert length(diffs) == 3
      assert {:added, to_add} in diffs
      assert {:removed, "remove_me"} in diffs
      assert {:updated, existing_new} in diffs
    end
  end

  # ── Batch 3: GenServer ETS population ────────────────────────────────────

  describe "GenServer: ETS population" do
    test "populates ETS store on first successful poll" do
      torrent = build_torrent("abc123")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [torrent]} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert [^torrent] = Store.get_all_torrents()
    end

    test "removes torrents from ETS when they disappear from rtorrent" do
      torrent = build_torrent("gone")
      Store.put_torrent(torrent)

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, []} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert Store.get_all_torrents() == []
    end

    test "updates an existing torrent in ETS when diff fields change" do
      old_torrent = build_torrent("h1", upload_rate: 0)
      new_torrent = build_torrent("h1", upload_rate: 999)
      Store.put_torrent(old_torrent)

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [new_torrent]} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert {:ok, ^new_torrent} = Store.get_torrent("h1")
    end
  end

  # ── Batch 4: GenServer PubSub broadcast ──────────────────────────────────

  describe "GenServer: PubSub broadcast" do
    test "broadcasts {:torrent_diffs, diffs} to torrents:list when torrents are added" do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:list")
      torrent = build_torrent("pub1")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [torrent]} end)

      pid = start_poller()
      send(pid, :poll)

      assert_receive {:torrent_diffs, [{:added, ^torrent}]}, 1_000
    end

    test "broadcasts {:torrent_updated, torrent} to torrents:{hash} for added torrent" do
      torrent = build_torrent("pub2")
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:pub2")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [torrent]} end)

      pid = start_poller()
      send(pid, :poll)

      assert_receive {:torrent_updated, ^torrent}, 1_000
    end

    test "does not broadcast when there are no diffs" do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:list")
      torrent = build_torrent("no_diff")
      Store.put_torrent(torrent)

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [torrent]} end)

      pid = start_poller()
      poll_and_wait(pid)

      refute_receive {:torrent_diffs, _}, 100
    end

    test "broadcasts :updated when a diff field changes between polls" do
      torrent_v1 = build_torrent("up1", upload_rate: 0)
      torrent_v2 = build_torrent("up1", upload_rate: 500)
      Store.put_torrent(torrent_v1)

      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:list")
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:up1")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [torrent_v2]} end)

      pid = start_poller()
      send(pid, :poll)

      assert_receive {:torrent_diffs, [{:updated, ^torrent_v2}]}, 1_000
      assert_receive {:torrent_updated, ^torrent_v2}, 1_000
    end
  end

  # ── Batch 5: GenServer error resilience ──────────────────────────────────

  describe "GenServer: error resilience" do
    test "increments consecutive_failures on RPC error" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()
      send(pid, :poll)
      state = :sys.get_state(pid)

      assert state.consecutive_failures == 1
    end

    test "GenServer stays alive after an RPC error" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :timeout} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert Process.alive?(pid)
    end

    test "resets consecutive_failures to 0 after a successful poll following failure" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)
      |> expect(:get_all_torrents, fn "" -> {:ok, []} end)

      pid = start_poller()

      send(pid, :poll)
      assert :sys.get_state(pid).consecutive_failures == 1

      send(pid, :poll)
      assert :sys.get_state(pid).consecutive_failures == 0
    end

    test "ETS is not modified on RPC error" do
      torrent = build_torrent("safe")
      Store.put_torrent(torrent)

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert {:ok, ^torrent} = Store.get_torrent("safe")
    end
  end
end
