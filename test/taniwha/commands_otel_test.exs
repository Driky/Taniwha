defmodule Taniwha.CommandsOtelTest do
  @moduledoc """
  Tests for OpenTelemetry span instrumentation on `Taniwha.Commands`.

  Verifies that each public function produces a correctly named span with the
  expected attributes. Because `Taniwha.Commands` is a plain module (not a
  GenServer), its spans automatically inherit the ambient OTel context of the
  caller's process — no explicit context propagation is needed.

  Must run `async: false` because we mutate the global `:otel_simple_processor`
  exporter state.
  """
  use ExUnit.Case, async: false

  import Mox
  import Taniwha.OtelTestHelper

  setup :verify_on_exit!
  setup :setup_otel_exporter

  defp stub_call(result) do
    Taniwha.RPC.MockClient
    |> expect(:call, fn _method, _params -> result end)
  end

  # Stubs the download_list RPC call returning empty hashes.
  # When hashes is [], fetch_all_torrent_data/1 short-circuits without calling multicall.
  defp stub_empty_list do
    Taniwha.RPC.MockClient
    |> expect(:call, fn "download_list", _ -> {:ok, []} end)
  end

  # ---------------------------------------------------------------------------
  # Torrent listing commands
  # ---------------------------------------------------------------------------

  describe "get_all_torrents/1 span" do
    test "creates taniwha.commands.get_all_torrents span" do
      stub_empty_list()
      Taniwha.Commands.get_all_torrents("")

      assert_span("taniwha.commands.get_all_torrents")
    end

    test "sets command.name attribute" do
      stub_empty_list()
      Taniwha.Commands.get_all_torrents("")

      assert_span("taniwha.commands.get_all_torrents",
        attributes: [{"command.name", "get_all_torrents"}]
      )
    end
  end

  describe "get_torrent/1 span" do
    test "creates taniwha.commands.get_torrent span with torrent.hash" do
      # Values must match the Torrent.rpc_fields() order and expected types
      # so that Torrent.from_rpc_values/2 doesn't raise
      rpc_values = [
        # d.name
        ["Test Torrent"],
        # d.size_bytes
        [1024],
        # d.completed_bytes
        [512],
        # d.up.rate
        [0],
        # d.down.rate
        [0],
        # d.ratio (raw integer, × 1000)
        [1000],
        # d.state (1 = started)
        [1],
        # d.is_active
        [0],
        # d.complete
        [0],
        # d.is_hash_checking
        [0],
        # d.peers_connected
        [3],
        # d.timestamp.started
        [1_620_000_000],
        # d.timestamp.finished
        [0],
        # d.base_path
        ["/downloads"],
        # d.custom1 (label)
        [""],
        # d.tracker_url
        [""]
      ]

      Taniwha.RPC.MockClient
      |> expect(:multicall, fn _calls -> {:ok, rpc_values} end)

      Taniwha.Commands.get_torrent("abc123")

      assert_span("taniwha.commands.get_torrent",
        attributes: [{"command.name", "get_torrent"}, {"torrent.hash", "abc123"}]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle commands
  # ---------------------------------------------------------------------------

  describe "lifecycle command spans" do
    test "start/1 creates span with torrent.hash" do
      stub_call({:ok, 0})
      Taniwha.Commands.start("deadbeef")

      assert_span("taniwha.commands.start",
        attributes: [{"command.name", "start"}, {"torrent.hash", "deadbeef"}]
      )
    end

    test "stop/1 creates span with torrent.hash" do
      stub_call({:ok, 0})
      Taniwha.Commands.stop("deadbeef")

      assert_span("taniwha.commands.stop",
        attributes: [{"command.name", "stop"}, {"torrent.hash", "deadbeef"}]
      )
    end

    test "erase/1 creates span with torrent.hash" do
      stub_call({:ok, 0})
      Taniwha.Commands.erase("deadbeef")

      assert_span("taniwha.commands.erase",
        attributes: [{"command.name", "erase"}, {"torrent.hash", "deadbeef"}]
      )
    end

    test "pause/1 creates span with torrent.hash" do
      stub_call({:ok, 0})
      Taniwha.Commands.pause("deadbeef")

      assert_span("taniwha.commands.pause",
        attributes: [{"command.name", "pause"}, {"torrent.hash", "deadbeef"}]
      )
    end

    test "resume/1 creates span with torrent.hash" do
      stub_call({:ok, 0})
      Taniwha.Commands.resume("deadbeef")

      assert_span("taniwha.commands.resume",
        attributes: [{"command.name", "resume"}, {"torrent.hash", "deadbeef"}]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Load commands
  # ---------------------------------------------------------------------------

  describe "load command spans" do
    test "load_url/1 creates span" do
      stub_call({:ok, 0})
      Taniwha.Commands.load_url("magnet:?xt=urn:btih:abc")

      assert_span("taniwha.commands.load_url",
        attributes: [{"command.name", "load_url"}]
      )
    end

    test "load_raw/1 creates span" do
      stub_call({:ok, 0})
      Taniwha.Commands.load_raw(<<1, 2, 3>>)

      assert_span("taniwha.commands.load_raw",
        attributes: [{"command.name", "load_raw"}]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # File / peer / tracker operations
  # ---------------------------------------------------------------------------

  describe "file/peer/tracker command spans" do
    test "list_files/1 creates span with torrent.hash" do
      stub_call({:ok, []})
      Taniwha.Commands.list_files("abc123")

      assert_span("taniwha.commands.list_files",
        attributes: [{"command.name", "list_files"}, {"torrent.hash", "abc123"}]
      )
    end

    test "set_file_priority/3 creates span with torrent.hash" do
      stub_call({:ok, 0})
      Taniwha.Commands.set_file_priority("abc123", 0, 1)

      assert_span("taniwha.commands.set_file_priority",
        attributes: [{"command.name", "set_file_priority"}, {"torrent.hash", "abc123"}]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Context nesting
  # ---------------------------------------------------------------------------

  describe "context nesting" do
    test "commands span is nested under ambient parent span" do
      stub_call({:ok, 0})

      require OpenTelemetry.Tracer

      OpenTelemetry.Tracer.with_span "test.parent" do
        Taniwha.Commands.start("abc")
      end

      child = assert_span("taniwha.commands.start")
      parent = assert_span("test.parent")

      assert parent_span_id(child) == span_id(parent)
    end
  end
end
