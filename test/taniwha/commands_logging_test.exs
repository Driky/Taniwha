defmodule Taniwha.CommandsLoggingTest do
  @moduledoc """
  Tests for structured log output from `Taniwha.Commands`.

  Verifies that write commands (lifecycle + load + file priority) emit a
  structured info log with `command` and `torrent_hash` metadata.

  Read operations (list_*, get_*, global_*) are not logged to avoid noise.

  Must run `async: false` because LogCapture modifies global :logger state.
  """

  use ExUnit.Case, async: false

  import Mox
  import Taniwha.LogCapture

  alias Taniwha.Commands

  setup :verify_on_exit!

  defp stub_ok do
    Taniwha.RPC.MockClient
    |> stub(:call, fn _method, _params -> {:ok, 0} end)
  end

  # ---------------------------------------------------------------------------
  # Lifecycle command logging
  # ---------------------------------------------------------------------------

  describe "lifecycle command logging" do
    test "start/1 emits info log with command=start and torrent_hash" do
      stub_ok()

      events =
        capture_log_events([level: :info], fn ->
          Commands.start("abc123")
        end)

      event = find_event(events, "Command executed")
      assert event != nil, "Expected to find 'Command executed' log event"
      assert log_meta(event, :command) == "start"
      assert log_meta(event, :torrent_hash) == "abc123"
    end

    test "stop/1 emits info log with command=stop" do
      stub_ok()

      events = capture_log_events([level: :info], fn -> Commands.stop("abc123") end)

      event = find_event(events, "Command executed")
      assert event != nil
      assert log_meta(event, :command) == "stop"
    end

    test "erase/1 emits info log with command=erase" do
      stub_ok()

      events = capture_log_events([level: :info], fn -> Commands.erase("abc123") end)

      event = find_event(events, "Command executed")
      assert event != nil
      assert log_meta(event, :command) == "erase"
    end
  end

  # ---------------------------------------------------------------------------
  # Load command logging
  # ---------------------------------------------------------------------------

  describe "load command logging" do
    test "load_url/1 emits info log with command=load_url" do
      Taniwha.RPC.MockClient
      |> expect(:call, fn "load.start", ["", _url] -> {:ok, 0} end)

      events =
        capture_log_events([level: :info], fn ->
          Commands.load_url("magnet:?xt=urn:btih:example")
        end)

      event = find_event(events, "Command executed")
      assert event != nil
      assert log_meta(event, :command) == "load_url"
    end

    test "load_raw/1 emits info log with command=load_raw" do
      Taniwha.RPC.MockClient
      |> expect(:call, fn "load.raw_start", ["", {:base64, _}] -> {:ok, 0} end)

      events =
        capture_log_events([level: :info], fn ->
          Commands.load_raw(<<1, 2, 3>>)
        end)

      event = find_event(events, "Command executed")
      assert event != nil
      assert log_meta(event, :command) == "load_raw"
    end
  end

  # ---------------------------------------------------------------------------
  # File priority logging
  # ---------------------------------------------------------------------------

  describe "file priority logging" do
    test "set_file_priority/3 emits info log with command and torrent_hash" do
      Taniwha.RPC.MockClient
      |> expect(:call, fn "f.priority.set", _params -> {:ok, 0} end)

      events =
        capture_log_events([level: :info], fn ->
          Commands.set_file_priority("abc123", 0, 1)
        end)

      event = find_event(events, "Command executed")
      assert event != nil
      assert log_meta(event, :command) == "set_file_priority"
      assert log_meta(event, :torrent_hash) == "abc123"
    end
  end

  # ---------------------------------------------------------------------------
  # Read operations — no logging
  # ---------------------------------------------------------------------------

  describe "read operations are not logged" do
    test "get_all_torrents does not emit a Command executed log" do
      Taniwha.RPC.MockClient
      |> stub(:call, fn "download_list", _ -> {:ok, []} end)
      |> stub(:multicall, fn _ -> {:ok, []} end)

      events =
        capture_log_events([level: :info], fn ->
          Commands.get_all_torrents("")
        end)

      assert find_event(events, "Command executed") == nil
    end
  end
end
