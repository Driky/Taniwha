defmodule TaniwhaWeb.TorrentChannelOtelTest do
  @moduledoc """
  Tests for OpenTelemetry span instrumentation on `TaniwhaWeb.TorrentChannel`.

  Verifies that each `handle_in` callback produces a correctly named and
  attributed span, and that error paths set the span status to error.

  Must run `async: false` because we mutate the global `:otel_simple_processor`
  exporter state.
  """
  use TaniwhaWeb.ChannelCase, async: false

  import Taniwha.OtelTestHelper
  import Taniwha.Test.Fixtures, only: [torrent_fixture: 0]

  alias Taniwha.State.Store
  alias TaniwhaWeb.{TorrentChannel, UserSocket}

  setup :setup_otel_exporter

  setup do
    {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    Store.clear()
    on_exit(fn -> Store.clear() end)
    {:ok, socket: socket}
  end

  defp join_list(socket) do
    {:ok, _reply, channel_socket} =
      subscribe_and_join(socket, TorrentChannel, "torrents:list")

    channel_socket
  end

  # ---------------------------------------------------------------------------
  # start event
  # ---------------------------------------------------------------------------

  describe "handle_in start" do
    test "creates taniwha.channel.start span", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:start, fn _hash -> :ok end)

      channel_socket = join_list(socket)
      push(channel_socket, "start", %{"hash" => "abc123"})
      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.start")
    end

    test "sets channel.event attribute", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:start, fn _hash -> :ok end)

      channel_socket = join_list(socket)
      push(channel_socket, "start", %{"hash" => "abc123"})
      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.start", attributes: [{"channel.event", "start"}])
    end

    test "sets channel.topic attribute", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:start, fn _hash -> :ok end)

      channel_socket = join_list(socket)
      push(channel_socket, "start", %{"hash" => "abc123"})
      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.start", attributes: [{"channel.topic", "torrents:list"}])
    end

    test "sets torrent.hash attribute", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:start, fn _hash -> :ok end)

      channel_socket = join_list(socket)
      push(channel_socket, "start", %{"hash" => "deadbeef"})
      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.start", attributes: [{"torrent.hash", "deadbeef"}])
    end

    test "sets error status when command fails", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:start, fn _hash -> {:error, :timeout} end)

      channel_socket = join_list(socket)
      push(channel_socket, "start", %{"hash" => "abc123"})
      :sys.get_state(channel_socket.channel_pid)

      span = assert_span("taniwha.channel.start")
      assert span_status(span) == :error
    end
  end

  # ---------------------------------------------------------------------------
  # stop event
  # ---------------------------------------------------------------------------

  describe "handle_in stop" do
    test "creates taniwha.channel.stop span with attributes", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:stop, fn _hash -> :ok end)

      channel_socket = join_list(socket)
      push(channel_socket, "stop", %{"hash" => "deadbeef"})
      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.stop",
        attributes: [
          {"channel.event", "stop"},
          {"channel.topic", "torrents:list"},
          {"torrent.hash", "deadbeef"}
        ]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # remove event
  # ---------------------------------------------------------------------------

  describe "handle_in remove" do
    test "creates taniwha.channel.remove span with attributes", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:erase, fn _hash -> :ok end)

      channel_socket = join_list(socket)
      push(channel_socket, "remove", %{"hash" => "deadbeef"})
      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.remove",
        attributes: [
          {"channel.event", "remove"},
          {"torrent.hash", "deadbeef"}
        ]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # set_file_priority event
  # ---------------------------------------------------------------------------

  describe "handle_in set_file_priority" do
    test "creates taniwha.channel.set_file_priority span with attributes", %{socket: socket} do
      Taniwha.MockCommands
      |> expect(:set_file_priority, fn _hash, _index, _priority -> :ok end)

      channel_socket = join_list(socket)

      push(channel_socket, "set_file_priority", %{
        "hash" => "abc123",
        "index" => 0,
        "priority" => 1
      })

      :sys.get_state(channel_socket.channel_pid)

      assert_span("taniwha.channel.set_file_priority",
        attributes: [
          {"channel.event", "set_file_priority"},
          {"torrent.hash", "abc123"}
        ]
      )
    end
  end
end
