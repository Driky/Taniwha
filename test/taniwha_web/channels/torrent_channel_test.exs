defmodule TaniwhaWeb.TorrentChannelTest do
  use TaniwhaWeb.ChannelCase, async: false

  alias Taniwha.{MockCommands, State.Store}
  alias TaniwhaWeb.{TorrentChannel, UserSocket}

  import Taniwha.Test.Fixtures, only: [torrent_fixture: 0, torrent_fixture: 1]

  setup do
    {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    Store.clear()
    on_exit(fn -> Store.clear() end)
    {:ok, socket: socket}
  end

  # ---------------------------------------------------------------------------
  # Batch 2: Join handlers
  # ---------------------------------------------------------------------------

  describe "join torrents:list" do
    test "returns snapshot of all torrents from Store", %{socket: socket} do
      torrent = torrent_fixture()
      Store.put_torrent(torrent)

      {:ok, reply, _socket} = subscribe_and_join(socket, TorrentChannel, "torrents:list")

      assert [torrent_map] = reply.torrents
      assert torrent_map["hash"] == torrent.hash
      assert torrent_map["name"] == "Test Torrent"
      assert torrent_map["size"] == 1_000_000
      assert torrent_map["completedBytes"] == 500_000
      assert torrent_map["state"] == "started"
      assert torrent_map["isActive"] == true
      assert torrent_map["progress"] == 0.5
      assert torrent_map["status"] == "downloading"
    end

    test "returns empty list when Store has no torrents", %{socket: socket} do
      {:ok, reply, _socket} = subscribe_and_join(socket, TorrentChannel, "torrents:list")

      assert reply.torrents == []
    end

    test "serializes optional datetime fields as nil when absent", %{socket: socket} do
      Store.put_torrent(torrent_fixture())

      {:ok, reply, _socket} = subscribe_and_join(socket, TorrentChannel, "torrents:list")

      [torrent_map] = reply.torrents
      assert is_nil(torrent_map["startedAt"])
      assert is_nil(torrent_map["finishedAt"])
    end

    test "serializes DateTime fields as ISO8601 strings when present", %{socket: socket} do
      dt = ~U[2025-01-15 12:00:00Z]
      torrent = %{torrent_fixture() | started_at: dt, finished_at: dt}
      Store.put_torrent(torrent)

      {:ok, reply, _socket} = subscribe_and_join(socket, TorrentChannel, "torrents:list")

      [torrent_map] = reply.torrents
      assert torrent_map["startedAt"] == "2025-01-15T12:00:00Z"
      assert torrent_map["finishedAt"] == "2025-01-15T12:00:00Z"
    end
  end

  describe "join torrents:{hash}" do
    test "returns the matching torrent when found", %{socket: socket} do
      hash = "deadbeef12345678deadbeef12345678"
      torrent = torrent_fixture(hash)
      Store.put_torrent(torrent)

      {:ok, reply, _socket} = subscribe_and_join(socket, TorrentChannel, "torrents:#{hash}")

      assert reply.torrent["hash"] == hash
      assert reply.torrent["name"] == "Test Torrent"
    end

    test "returns error when torrent is not in Store", %{socket: socket} do
      {:error, reason} =
        subscribe_and_join(socket, TorrentChannel, "torrents:nosuchhashatall12345678")

      assert reason == %{reason: "torrent_not_found"}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3: Command handle_in
  # ---------------------------------------------------------------------------

  describe "handle_in commands on torrents:list" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, TorrentChannel, "torrents:list")
      {:ok, channel: channel}
    end

    @valid_hash String.duplicate("a", 40)

    test "start delegates to @commands and replies :ok", %{channel: channel} do
      expect(MockCommands, :start, fn @valid_hash -> :ok end)
      ref = push(channel, "start", %{"hash" => @valid_hash})
      assert_reply ref, :ok
    end

    test "stop delegates to @commands and replies :ok", %{channel: channel} do
      expect(MockCommands, :stop, fn @valid_hash -> :ok end)
      ref = push(channel, "stop", %{"hash" => @valid_hash})
      assert_reply ref, :ok
    end

    test "remove delegates to Commands.erase/1 and replies :ok", %{channel: channel} do
      expect(MockCommands, :erase, fn @valid_hash -> :ok end)
      ref = push(channel, "remove", %{"hash" => @valid_hash})
      assert_reply ref, :ok
    end

    test "set_file_priority delegates to @commands and replies :ok", %{channel: channel} do
      expect(MockCommands, :set_file_priority, fn @valid_hash, 0, 1 -> :ok end)

      ref =
        push(channel, "set_file_priority", %{"hash" => @valid_hash, "index" => 0, "priority" => 1})

      assert_reply ref, :ok
    end

    test "command failure replies with {:error, reason}", %{channel: channel} do
      expect(MockCommands, :start, fn _hash -> {:error, :connection_refused} end)
      ref = push(channel, "start", %{"hash" => @valid_hash})
      assert_reply ref, :error, %{reason: _reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4: PubSub handle_info
  # ---------------------------------------------------------------------------

  describe "handle_info PubSub messages on torrents:list" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, TorrentChannel, "torrents:list")
      {:ok, channel: channel}
    end

    test "torrent_diffs message pushes diffs event to client", %{channel: channel} do
      torrent = torrent_fixture()
      send(channel.channel_pid, {:torrent_diffs, [{:added, torrent}]})

      assert_push "diffs", %{diffs: [diff]}
      assert diff["type"] == "added"
      assert diff["data"]["hash"] == torrent.hash
      assert diff["data"]["name"] == "Test Torrent"
    end

    test "torrent_diffs with removed entry sends hash only", %{channel: channel} do
      hash = "deadbeef12345678deadbeef12345678"
      send(channel.channel_pid, {:torrent_diffs, [{:removed, hash}]})

      assert_push "diffs", %{diffs: [diff]}
      assert diff["type"] == "removed"
      assert diff["data"] == %{"hash" => hash}
    end

    test "torrent_diffs with updated entry serializes torrent", %{channel: channel} do
      torrent = torrent_fixture()
      send(channel.channel_pid, {:torrent_diffs, [{:updated, torrent}]})

      assert_push "diffs", %{diffs: [diff]}
      assert diff["type"] == "updated"
      assert diff["data"]["hash"] == torrent.hash
    end

    test "torrent_updated message pushes updated event to client", %{channel: channel} do
      torrent = torrent_fixture()
      send(channel.channel_pid, {:torrent_updated, torrent})

      assert_push "updated", %{torrent: torrent_map}
      assert torrent_map["hash"] == torrent.hash
      assert torrent_map["name"] == "Test Torrent"
    end
  end

  describe "handle_info PubSub messages on torrents:{hash}" do
    setup %{socket: socket} do
      hash = "deadbeef12345678deadbeef12345678"
      torrent = torrent_fixture(hash)
      Store.put_torrent(torrent)
      {:ok, _reply, channel} = subscribe_and_join(socket, TorrentChannel, "torrents:#{hash}")
      {:ok, channel: channel, torrent: torrent}
    end

    test "torrent_updated message pushes updated event to client", %{
      channel: channel,
      torrent: torrent
    } do
      send(channel.channel_pid, {:torrent_updated, torrent})

      assert_push "updated", %{torrent: torrent_map}
      assert torrent_map["hash"] == torrent.hash
    end
  end

  # ---------------------------------------------------------------------------
  # Batch: Input validation
  # ---------------------------------------------------------------------------

  describe "input validation" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, TorrentChannel, "torrents:list")
      {:ok, channel: channel}
    end

    test "start with hash shorter than 40 chars is rejected", %{channel: channel} do
      ref = push(channel, "start", %{"hash" => "tooshort"})
      assert_reply ref, :error, %{reason: "invalid hash"}
    end

    test "start with non-hex 40-char hash is rejected", %{channel: channel} do
      ref = push(channel, "start", %{"hash" => String.duplicate("g", 40)})
      assert_reply ref, :error, %{reason: "invalid hash"}
    end

    test "stop with invalid hash is rejected", %{channel: channel} do
      ref = push(channel, "stop", %{"hash" => "bad"})
      assert_reply ref, :error, %{reason: "invalid hash"}
    end

    test "remove with invalid hash is rejected", %{channel: channel} do
      ref = push(channel, "remove", %{"hash" => "bad"})
      assert_reply ref, :error, %{reason: "invalid hash"}
    end

    test "set_file_priority with invalid priority value is rejected", %{channel: channel} do
      ref =
        push(channel, "set_file_priority", %{
          "hash" => String.duplicate("a", 40),
          "index" => 0,
          "priority" => 5
        })

      assert_reply ref, :error, %{reason: "invalid priority"}
    end

    test "set_file_priority with invalid hash is rejected", %{channel: channel} do
      ref =
        push(channel, "set_file_priority", %{
          "hash" => "short",
          "index" => 0,
          "priority" => 1
        })

      assert_reply ref, :error, %{reason: "invalid hash"}
    end

    test "start with valid 40-char hex hash is accepted", %{channel: channel} do
      import Mox
      expect(MockCommands, :start, fn _hash -> :ok end)

      ref = push(channel, "start", %{"hash" => String.duplicate("a", 40)})
      assert_reply ref, :ok
    end
  end
end
