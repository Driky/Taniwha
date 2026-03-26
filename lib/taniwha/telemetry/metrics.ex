defmodule Taniwha.Telemetry.Metrics do
  @moduledoc """
  Custom telemetry metrics for Taniwha.

  Emits `:telemetry` events for all domain-specific measurements. The
  `metrics/0` function returns `Telemetry.Metrics` spec structs suitable for
  reporters (Prometheus, Phoenix LiveDashboard, etc.).

  ## Telemetry events

  | Event | Measurements | Metadata |
  |---|---|---|
  | `[:taniwha, :rpc, :call]` | `duration_ms`, `response_size` | `rpc_method` |
  | `[:taniwha, :rpc, :error]` | `count` | `error_type` |
  | `[:taniwha, :poller, :cycle]` | `duration_ms`, `torrent_count`, `diff_count` | — |
  | `[:taniwha, :poller, :failure]` | `count` | — |
  | `[:taniwha, :commands, :call]` | `count` | `command_name` |
  | `[:taniwha, :torrents, :stats]` | `active`, `total`, `download_speed`, `upload_speed` | — |
  | `[:taniwha, :websocket, :connections]` | `delta` | — |

  See `docs/observability.md` for the full metric catalogue and naming
  conventions.

  ## Usage

      # In Poller after a successful poll:
      Taniwha.Telemetry.Metrics.record_poller_cycle(duration_ms, torrent_count, diff_count)
      Taniwha.Telemetry.Metrics.update_torrent_stats(active, total, download_speed, upload_speed)

      # In RPC.Client after a call:
      Taniwha.Telemetry.Metrics.record_rpc_call(method, duration_ms)

      # In Channel on join/terminate:
      Taniwha.Telemetry.Metrics.inc_websocket_connections()
      Taniwha.Telemetry.Metrics.dec_websocket_connections()
  """

  import Telemetry.Metrics, only: [distribution: 2, last_value: 2, counter: 2, sum: 2]

  # ---------------------------------------------------------------------------
  # Metric spec definitions
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of `Telemetry.Metrics` specs for this application.

  Attach a reporter (e.g., `TelemetryMetricsPrometheus`) to consume these.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      # RPC distributions
      distribution("taniwha.rpc.call.duration_ms",
        event_name: [:taniwha, :rpc, :call],
        measurement: :duration_ms,
        tags: [:rpc_method],
        unit: {:native, :millisecond},
        description: "Distribution of RPC call durations in milliseconds"
      ),

      # RPC counters
      counter("taniwha.rpc.errors.total",
        event_name: [:taniwha, :rpc, :error],
        measurement: :count,
        tags: [:error_type],
        description: "Total number of RPC errors"
      ),

      # Poller distributions
      distribution("taniwha.poller.cycle.duration_ms",
        event_name: [:taniwha, :poller, :cycle],
        measurement: :duration_ms,
        unit: {:native, :millisecond},
        description: "Distribution of poll cycle durations in milliseconds"
      ),

      # Poller last values
      last_value("taniwha.poller.cycle.torrent_count",
        event_name: [:taniwha, :poller, :cycle],
        measurement: :torrent_count,
        description: "Number of torrents fetched in the last poll cycle"
      ),

      # Poller counters
      counter("taniwha.poller.failures.total",
        event_name: [:taniwha, :poller, :failure],
        measurement: :count,
        description: "Total number of failed poll cycles"
      ),

      # Commands counter
      counter("taniwha.commands.calls.total",
        event_name: [:taniwha, :commands, :call],
        measurement: :count,
        tags: [:command_name],
        description: "Total number of command calls"
      ),

      # Torrent stats gauges
      last_value("taniwha.torrents.active",
        event_name: [:taniwha, :torrents, :stats],
        measurement: :active,
        description: "Number of active (downloading or seeding) torrents"
      ),
      last_value("taniwha.torrents.total",
        event_name: [:taniwha, :torrents, :stats],
        measurement: :total,
        description: "Total number of torrents"
      ),
      last_value("taniwha.torrents.download_speed",
        event_name: [:taniwha, :torrents, :stats],
        measurement: :download_speed,
        description: "Global download speed in bytes per second"
      ),
      last_value("taniwha.torrents.upload_speed",
        event_name: [:taniwha, :torrents, :stats],
        measurement: :upload_speed,
        description: "Global upload speed in bytes per second"
      ),

      # WebSocket connections (sum acts as up/down counter)
      sum("taniwha.websocket.connections",
        event_name: [:taniwha, :websocket, :connections],
        measurement: :delta,
        description: "Number of connected WebSocket clients (cumulative delta)"
      )
    ]
  end

  # ---------------------------------------------------------------------------
  # Measurement update functions
  # ---------------------------------------------------------------------------

  @doc """
  Records the duration and result counts for a completed poll cycle.

  `duration_ms` is the wall-clock time of the cycle in milliseconds.
  `torrent_count` is the number of torrents returned by rtorrent.
  `diff_count` is the number of changes detected.
  """
  @spec record_poller_cycle(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def record_poller_cycle(duration_ms, torrent_count, diff_count) do
    :telemetry.execute(
      [:taniwha, :poller, :cycle],
      %{duration_ms: duration_ms, torrent_count: torrent_count, diff_count: diff_count},
      %{}
    )
  end

  @doc "Increments the failed poll cycle counter."
  @spec record_poller_failure() :: :ok
  def record_poller_failure do
    :telemetry.execute([:taniwha, :poller, :failure], %{count: 1}, %{})
  end

  @doc """
  Records the duration of a single RPC call.

  `method` is the rtorrent RPC method name (e.g., `"d.name"`).
  `duration_ms` is the wall-clock time in milliseconds.
  """
  @spec record_rpc_call(String.t(), non_neg_integer()) :: :ok
  def record_rpc_call(method, duration_ms) do
    :telemetry.execute(
      [:taniwha, :rpc, :call],
      %{duration_ms: duration_ms, response_size: 0},
      %{rpc_method: method}
    )
  end

  @doc """
  Increments the RPC error counter.

  `error_type` is a string representation of the error reason.
  """
  @spec record_rpc_error(String.t()) :: :ok
  def record_rpc_error(error_type) do
    :telemetry.execute([:taniwha, :rpc, :error], %{count: 1}, %{error_type: error_type})
  end

  @doc """
  Increments the command call counter.

  `command_name` is the name of the function called (e.g., `"start"`).
  """
  @spec record_command(String.t()) :: :ok
  def record_command(command_name) do
    :telemetry.execute([:taniwha, :commands, :call], %{count: 1}, %{command_name: command_name})
  end

  @doc """
  Updates the torrent stats gauges.

  Called by the Poller after each successful poll cycle.
  """
  @spec update_torrent_stats(
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def update_torrent_stats(active, total, download_speed, upload_speed) do
    :telemetry.execute(
      [:taniwha, :torrents, :stats],
      %{
        active: active,
        total: total,
        download_speed: download_speed,
        upload_speed: upload_speed
      },
      %{}
    )
  end

  @doc "Increments the WebSocket connections gauge by 1."
  @spec inc_websocket_connections() :: :ok
  def inc_websocket_connections do
    :telemetry.execute([:taniwha, :websocket, :connections], %{delta: 1}, %{})
  end

  @doc "Decrements the WebSocket connections gauge by 1."
  @spec dec_websocket_connections() :: :ok
  def dec_websocket_connections do
    :telemetry.execute([:taniwha, :websocket, :connections], %{delta: -1}, %{})
  end
end
