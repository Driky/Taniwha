defmodule Taniwha.CommandsTest do
  use ExUnit.Case, async: true

  import Mox

  alias Taniwha.Commands
  alias Taniwha.Torrent
  alias Taniwha.TorrentFile

  setup :verify_on_exit!

  # Raw RPC values in Torrent.rpc_fields/0 order, with optional overrides.
  defp torrent_rpc_values(overrides \\ %{}) do
    defaults = %{
      name: "My Torrent",
      size: 1_000_000,
      completed_bytes: 500_000,
      up_rate: 100,
      down_rate: 200,
      ratio: 1500,
      state: 1,
      is_active: 1,
      complete: 0,
      is_hash_checking: 0,
      peers_connected: 3,
      ts_started: 1_609_459_200,
      ts_finished: 0,
      base_path: "/downloads"
    }

    m = Map.merge(defaults, overrides)

    [
      m.name,
      m.size,
      m.completed_bytes,
      m.up_rate,
      m.down_rate,
      m.ratio,
      m.state,
      m.is_active,
      m.complete,
      m.is_hash_checking,
      m.peers_connected,
      m.ts_started,
      m.ts_finished,
      m.base_path
    ]
  end

  # Wrap each value in [v] as system.multicall does.
  defp wrap_multicall(values), do: Enum.map(values, fn v -> [v] end)

  # ---------------------------------------------------------------------------
  # Batch 1 — list_hashes/1
  # ---------------------------------------------------------------------------

  describe "list_hashes/1" do
    test "returns list of hashes with default view" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", [""] ->
        {:ok, ["hash1", "hash2"]}
      end)

      assert Commands.list_hashes() == {:ok, ["hash1", "hash2"]}
    end

    test "passes custom view param" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", ["main"] ->
        {:ok, ["hash1"]}
      end)

      assert Commands.list_hashes("main") == {:ok, ["hash1"]}
    end

    test "propagates RPC error" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", [""] ->
        {:error, :timeout}
      end)

      assert Commands.list_hashes() == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — get_torrent/1
  # ---------------------------------------------------------------------------

  describe "get_torrent/1" do
    test "calls multicall with correct field/hash pairs" do
      hash = "abc123"
      fields = Torrent.rpc_fields()
      expected_calls = Enum.map(fields, fn field -> {field, [hash]} end)

      expect(Taniwha.RPC.MockClient, :multicall, fn calls ->
        assert calls == expected_calls
        {:ok, wrap_multicall(torrent_rpc_values())}
      end)

      assert {:ok, %Torrent{hash: "abc123"}} = Commands.get_torrent(hash)
    end

    test "builds a Torrent struct from multicall results" do
      hash = "xyz"

      expect(Taniwha.RPC.MockClient, :multicall, fn _ ->
        {:ok, wrap_multicall(torrent_rpc_values())}
      end)

      {:ok, torrent} = Commands.get_torrent(hash)
      assert torrent.hash == hash
      assert torrent.name == "My Torrent"
      assert torrent.size == 1_000_000
      assert torrent.completed_bytes == 500_000
    end

    test "propagates RPC error" do
      expect(Taniwha.RPC.MockClient, :multicall, fn _ -> {:error, :timeout} end)
      assert Commands.get_torrent("abc123") == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — lifecycle commands
  # ---------------------------------------------------------------------------

  describe "start/1" do
    test "calls d.start and returns :ok on success" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.start", ["hash123"] -> {:ok, 0} end)
      assert Commands.start("hash123") == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.start", _ -> {:error, :timeout} end)
      assert Commands.start("hash123") == {:error, :timeout}
    end
  end

  describe "stop/1" do
    test "calls d.stop and returns :ok on success" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.stop", ["hash123"] -> {:ok, 0} end)
      assert Commands.stop("hash123") == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.stop", _ -> {:error, :timeout} end)
      assert Commands.stop("hash123") == {:error, :timeout}
    end
  end

  describe "close/1" do
    test "calls d.close and returns :ok on success" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.close", ["hash123"] -> {:ok, 0} end)
      assert Commands.close("hash123") == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.close", _ -> {:error, :timeout} end)
      assert Commands.close("hash123") == {:error, :timeout}
    end
  end

  describe "erase/1" do
    test "calls d.erase and returns :ok on success" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["hash123"] -> {:ok, 0} end)
      assert Commands.erase("hash123") == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.erase", _ -> {:error, :timeout} end)
      assert Commands.erase("hash123") == {:error, :timeout}
    end
  end

  describe "pause/1" do
    test "calls d.pause and returns :ok on success" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.pause", ["hash123"] -> {:ok, 0} end)
      assert Commands.pause("hash123") == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.pause", _ -> {:error, :timeout} end)
      assert Commands.pause("hash123") == {:error, :timeout}
    end
  end

  describe "resume/1" do
    test "calls d.resume and returns :ok on success" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.resume", ["hash123"] -> {:ok, 0} end)
      assert Commands.resume("hash123") == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.resume", _ -> {:error, :timeout} end)
      assert Commands.resume("hash123") == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — load_url/1 and load_raw/1
  # ---------------------------------------------------------------------------

  describe "load_url/1" do
    test "calls load.start with empty target and url" do
      url = "http://example.com/file.torrent"

      expect(Taniwha.RPC.MockClient, :call, fn "load.start", ["", ^url] -> {:ok, 0} end)

      assert Commands.load_url(url) == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.start", _ -> {:error, :timeout} end)
      assert Commands.load_url("http://example.com/file.torrent") == {:error, :timeout}
    end
  end

  describe "load_raw/1" do
    test "calls load.raw_start with empty target and raw data" do
      data = <<0, 1, 2, 3>>

      expect(Taniwha.RPC.MockClient, :call, fn "load.raw_start", ["", ^data] -> {:ok, 0} end)

      assert Commands.load_raw(data) == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.raw_start", _ -> {:error, :timeout} end)
      assert Commands.load_raw(<<>>) == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 5 — list_files/1
  # ---------------------------------------------------------------------------

  describe "list_files/1" do
    test "calls f.multicall with correct params and parses TorrentFile structs" do
      hash = "abc123"

      expect(Taniwha.RPC.MockClient, :call, fn "f.multicall",
                                               [
                                                 ^hash,
                                                 "",
                                                 "f.path=",
                                                 "f.size_bytes=",
                                                 "f.priority=",
                                                 "f.completed_chunks=",
                                                 "f.size_chunks="
                                               ] ->
        {:ok,
         [
           ["/downloads/file1.mkv", 700_000_000, 1, 8000, 10_000],
           ["/downloads/file2.srt", 100_000, 0, 0, 100]
         ]}
      end)

      {:ok, files} = Commands.list_files(hash)
      assert length(files) == 2

      assert hd(files) == %TorrentFile{
               path: "/downloads/file1.mkv",
               size: 700_000_000,
               priority: 1,
               completed_chunks: 8000,
               total_chunks: 10_000
             }
    end

    test "handles empty file list" do
      expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", _ -> {:ok, []} end)
      assert Commands.list_files("abc123") == {:ok, []}
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", _ -> {:error, :timeout} end)
      assert Commands.list_files("abc123") == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6 — set_file_priority/3
  # ---------------------------------------------------------------------------

  describe "set_file_priority/3" do
    test "calls f.priority.set with hash:fN format" do
      expect(Taniwha.RPC.MockClient, :call, fn "f.priority.set", ["abc123:f2", 0] ->
        {:ok, 0}
      end)

      assert Commands.set_file_priority("abc123", 2, 0) == :ok
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "f.priority.set", _ -> {:error, :timeout} end)
      assert Commands.set_file_priority("abc123", 0, 1) == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 7 — global_up_rate/0 and global_down_rate/0
  # ---------------------------------------------------------------------------

  describe "global_up_rate/0" do
    test "returns upload rate integer" do
      expect(Taniwha.RPC.MockClient, :call, fn "throttle.global_up.rate", [] ->
        {:ok, 1_024_000}
      end)

      assert Commands.global_up_rate() == {:ok, 1_024_000}
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "throttle.global_up.rate", [] ->
        {:error, :timeout}
      end)

      assert Commands.global_up_rate() == {:error, :timeout}
    end
  end

  describe "global_down_rate/0" do
    test "returns download rate integer" do
      expect(Taniwha.RPC.MockClient, :call, fn "throttle.global_down.rate", [] ->
        {:ok, 5_242_880}
      end)

      assert Commands.global_down_rate() == {:ok, 5_242_880}
    end

    test "propagates error" do
      expect(Taniwha.RPC.MockClient, :call, fn "throttle.global_down.rate", [] ->
        {:error, :timeout}
      end)

      assert Commands.global_down_rate() == {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — get_all_torrents/1
  # ---------------------------------------------------------------------------

  describe "get_all_torrents/1" do
    test "returns empty list when no hashes" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", [""] -> {:ok, []} end)
      assert Commands.get_all_torrents() == {:ok, []}
    end

    test "fetches all torrents in a single batched multicall" do
      hashes = ["hash1", "hash2"]
      fields = Torrent.rpc_fields()
      expected_calls = for hash <- hashes, field <- fields, do: {field, [hash]}

      values1 = torrent_rpc_values(%{name: "Torrent 1"})
      values2 = torrent_rpc_values(%{name: "Torrent 2", size: 2_000_000})
      all_results = wrap_multicall(values1 ++ values2)

      expect(Taniwha.RPC.MockClient, :call, fn "download_list", [""] -> {:ok, hashes} end)

      expect(Taniwha.RPC.MockClient, :multicall, fn calls ->
        assert calls == expected_calls
        {:ok, all_results}
      end)

      {:ok, torrents} = Commands.get_all_torrents()
      assert length(torrents) == 2
      assert Enum.at(torrents, 0).name == "Torrent 1"
      assert Enum.at(torrents, 1).name == "Torrent 2"
    end

    test "passes custom view param" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", ["main"] -> {:ok, []} end)
      assert Commands.get_all_torrents("main") == {:ok, []}
    end

    test "propagates error from list_hashes" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", [""] ->
        {:error, :timeout}
      end)

      assert Commands.get_all_torrents() == {:error, :timeout}
    end

    test "propagates error from multicall" do
      expect(Taniwha.RPC.MockClient, :call, fn "download_list", [""] -> {:ok, ["hash1"]} end)
      expect(Taniwha.RPC.MockClient, :multicall, fn _ -> {:error, :timeout} end)
      assert Commands.get_all_torrents() == {:error, :timeout}
    end
  end
end
