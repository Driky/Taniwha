defmodule Taniwha.Telemetry.MetricsTest do
  @moduledoc """
  Tests for `Taniwha.Telemetry.Metrics`.

  Verifies that each update function emits the correct `:telemetry` event with
  the expected measurements and metadata. Uses `:telemetry.attach/4` to capture
  events during tests and detaches in `on_exit`.
  """
  use ExUnit.Case, async: true

  alias Taniwha.Telemetry.Metrics

  # Attach a handler that sends the event to the test process and detach it
  # when the test is done.
  defp attach_handler(event_name) do
    handler_id = {__MODULE__, event_name, self()}

    :telemetry.attach(
      handler_id,
      event_name,
      fn ^event_name, measurements, metadata, _config ->
        send(self(), {:telemetry_event, event_name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  # ---------------------------------------------------------------------------
  # Poller metrics
  # ---------------------------------------------------------------------------

  describe "record_poller_cycle/3" do
    test "emits [:taniwha, :poller, :cycle] event" do
      attach_handler([:taniwha, :poller, :cycle])
      Metrics.record_poller_cycle(42, 10, 3)
      assert_receive {:telemetry_event, [:taniwha, :poller, :cycle], measurements, _meta}
      assert measurements.duration_ms == 42
      assert measurements.torrent_count == 10
      assert measurements.diff_count == 3
    end
  end

  describe "record_poller_failure/0" do
    test "emits [:taniwha, :poller, :failure] event with count 1" do
      attach_handler([:taniwha, :poller, :failure])
      Metrics.record_poller_failure()
      assert_receive {:telemetry_event, [:taniwha, :poller, :failure], %{count: 1}, _meta}
    end
  end

  # ---------------------------------------------------------------------------
  # RPC metrics
  # ---------------------------------------------------------------------------

  describe "record_rpc_call/2" do
    test "emits [:taniwha, :rpc, :call] event with duration and method" do
      attach_handler([:taniwha, :rpc, :call])
      Metrics.record_rpc_call("d.name", 15)
      assert_receive {:telemetry_event, [:taniwha, :rpc, :call], measurements, metadata}
      assert measurements.duration_ms == 15
      assert metadata.rpc_method == "d.name"
    end
  end

  describe "record_rpc_error/1" do
    test "emits [:taniwha, :rpc, :error] event with count 1 and error_type" do
      attach_handler([:taniwha, :rpc, :error])
      Metrics.record_rpc_error(":econnrefused")
      assert_receive {:telemetry_event, [:taniwha, :rpc, :error], %{count: 1}, metadata}
      assert metadata.error_type == ":econnrefused"
    end
  end

  # ---------------------------------------------------------------------------
  # Commands metrics
  # ---------------------------------------------------------------------------

  describe "record_command/1" do
    test "emits [:taniwha, :commands, :call] event with count 1 and command_name" do
      attach_handler([:taniwha, :commands, :call])
      Metrics.record_command("start")
      assert_receive {:telemetry_event, [:taniwha, :commands, :call], %{count: 1}, metadata}
      assert metadata.command_name == "start"
    end
  end

  # ---------------------------------------------------------------------------
  # Torrent stats metrics
  # ---------------------------------------------------------------------------

  describe "update_torrent_stats/4" do
    test "emits [:taniwha, :torrents, :stats] event with all measurements" do
      attach_handler([:taniwha, :torrents, :stats])
      Metrics.update_torrent_stats(5, 12, 1024, 512)
      assert_receive {:telemetry_event, [:taniwha, :torrents, :stats], measurements, _meta}
      assert measurements.active == 5
      assert measurements.total == 12
      assert measurements.download_speed == 1024
      assert measurements.upload_speed == 512
    end
  end

  # ---------------------------------------------------------------------------
  # WebSocket connections metrics
  # ---------------------------------------------------------------------------

  describe "inc_websocket_connections/0" do
    test "emits [:taniwha, :websocket, :connections] event with delta +1" do
      attach_handler([:taniwha, :websocket, :connections])
      Metrics.inc_websocket_connections()
      assert_receive {:telemetry_event, [:taniwha, :websocket, :connections], %{delta: 1}, _}
    end
  end

  describe "dec_websocket_connections/0" do
    test "emits [:taniwha, :websocket, :connections] event with delta -1" do
      attach_handler([:taniwha, :websocket, :connections])
      Metrics.dec_websocket_connections()
      assert_receive {:telemetry_event, [:taniwha, :websocket, :connections], %{delta: -1}, _}
    end
  end

  # ---------------------------------------------------------------------------
  # Metric specs
  # ---------------------------------------------------------------------------

  describe "metrics/0" do
    test "returns a non-empty list of Telemetry.Metrics specs" do
      specs = Metrics.metrics()
      assert is_list(specs)
      assert length(specs) > 0
    end

    test "includes a spec for rpc call duration" do
      # Telemetry.Metrics stores names as atom lists
      names = Enum.map(Metrics.metrics(), & &1.name)
      assert [:taniwha, :rpc, :call, :duration_ms] in names
    end

    test "includes a spec for poller cycle duration" do
      names = Enum.map(Metrics.metrics(), & &1.name)
      assert [:taniwha, :poller, :cycle, :duration_ms] in names
    end

    test "includes a spec for websocket connections" do
      names = Enum.map(Metrics.metrics(), & &1.name)
      assert [:taniwha, :websocket, :connections] in names
    end
  end
end
