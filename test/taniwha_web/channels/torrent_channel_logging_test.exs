defmodule TaniwhaWeb.TorrentChannelLoggingTest do
  @moduledoc """
  Tests for structured log output from `TaniwhaWeb.TorrentChannel`.

  Verifies that each inbound command emits a structured info log with
  channel_topic, event, and torrent_hash metadata.

  Must run `async: false` because LogCapture modifies global :logger state.
  """

  use TaniwhaWeb.ChannelCase, async: false

  import Mox
  import Taniwha.LogCapture

  alias TaniwhaWeb.UserSocket

  @valid_hash String.duplicate("a", 40)

  setup :verify_on_exit!

  setup do
    Taniwha.MockCommands
    |> stub(:get_all_torrents, fn _ -> {:ok, []} end)

    {:ok, _, socket} =
      UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(TaniwhaWeb.TorrentChannel, "torrents:list")

    {:ok, socket: socket}
  end

  # ---------------------------------------------------------------------------
  # Command logging
  # ---------------------------------------------------------------------------

  describe "channel command logging" do
    test "start command emits info log with channel_topic and torrent_hash", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:start, fn @valid_hash -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "start", %{"hash" => @valid_hash})
          # Wait for the channel to process the message
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil, "Expected to find 'Channel command received' log event"
      assert log_meta(event, :channel_topic) == "torrents:list"
      assert log_meta(event, :torrent_hash) == @valid_hash
      assert log_meta(event, :event) == "start"
    end

    test "stop command emits info log with event=stop", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:stop, fn @valid_hash -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "stop", %{"hash" => @valid_hash})
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil
      assert log_meta(event, :event) == "stop"
    end

    test "remove command emits info log with event=remove", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:erase, fn @valid_hash -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "remove", %{"hash" => @valid_hash})
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil
      assert log_meta(event, :event) == "remove"
    end

    test "set_file_priority command emits info log", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:set_file_priority, fn @valid_hash, 0, 1 -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "set_file_priority", %{
            "hash" => @valid_hash,
            "index" => 0,
            "priority" => 1
          })

          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil
      assert log_meta(event, :event) == "set_file_priority"
      assert log_meta(event, :torrent_hash) == @valid_hash
    end
  end
end
