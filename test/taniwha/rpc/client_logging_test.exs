defmodule Taniwha.RPC.ClientLoggingTest do
  @moduledoc """
  Tests for structured log output from `Taniwha.RPC.Client`.

  Verifies that RPC call failures emit a structured warning log with
  rpc_method, error_reason, and transport metadata.

  Must run `async: false` because:
  - RPC.Client is a globally-named GenServer.
  - LogCapture modifies global :logger state.
  """

  use ExUnit.Case, async: false

  import Mox
  import Taniwha.LogCapture

  alias Taniwha.RPC.Client
  alias Taniwha.SCGI.MockConnection

  setup :verify_on_exit!

  setup do
    Mox.allow(MockConnection, self(), Process.whereis(Client))
    :ok
  end

  # ---------------------------------------------------------------------------
  # RPC call failure logging
  # ---------------------------------------------------------------------------

  describe "RPC call failure logging" do
    test "call/2 failure emits warning with rpc_method in metadata" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:error, :enoent} end)

      events =
        capture_log_events([level: :warning], fn ->
          Client.call("d.start", ["abc123"])
        end)

      event = find_event(events, "RPC call failed")
      assert event != nil, "Expected to find 'RPC call failed' log event"
      assert log_meta(event, :rpc_method) == "d.start"
    end

    test "call/2 failure emits warning with error_reason in metadata" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:error, :econnrefused} end)

      events =
        capture_log_events([level: :warning], fn ->
          Client.call("d.name", ["abc123"])
        end)

      event = find_event(events, "RPC call failed")
      assert event != nil
      assert log_meta(event, :error_reason) == ":connection_failed"
    end

    test "call/2 failure emits warning with transport in metadata" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:error, :enoent} end)

      events =
        capture_log_events([level: :warning], fn ->
          Client.call("d.start", ["abc123"])
        end)

      event = find_event(events, "RPC call failed")
      assert event != nil
      assert log_meta(event, :transport) == "unix"
    end

    test "call/2 success does NOT emit a warning" do
      scgi_response =
        "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n" <>
          "<?xml version=\"1.0\"?><methodResponse><params><param><value><string>My Torrent</string></value></param></params></methodResponse>"

      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:ok, scgi_response} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      events = capture_log_events([level: :warning], fn -> Client.call("d.name", ["abc123"]) end)

      assert find_event(events, "RPC call failed") == nil
    end
  end
end
