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
      |> expect(:start, fn "abc123" -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "start", %{"hash" => "abc123"})
          # Wait for the channel to process the message
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil, "Expected to find 'Channel command received' log event"
      assert log_meta(event, :channel_topic) == "torrents:list"
      assert log_meta(event, :torrent_hash) == "abc123"
      assert log_meta(event, :event) == "start"
    end

    test "stop command emits info log with event=stop", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:stop, fn "abc123" -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "stop", %{"hash" => "abc123"})
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil
      assert log_meta(event, :event) == "stop"
    end

    test "remove command emits info log with event=remove", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:erase, fn "abc123" -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "remove", %{"hash" => "abc123"})
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil
      assert log_meta(event, :event) == "remove"
    end

    test "set_file_priority command emits info log", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:set_file_priority, fn "abc123", 0, 1 -> :ok end)

      events =
        capture_log_events([level: :info], fn ->
          push(socket, "set_file_priority", %{"hash" => "abc123", "index" => 0, "priority" => 1})
          :sys.get_state(socket.channel_pid)
        end)

      event = find_event(events, "Channel command received")
      assert event != nil
      assert log_meta(event, :event) == "set_file_priority"
      assert log_meta(event, :torrent_hash) == "abc123"
    end
  end
end
