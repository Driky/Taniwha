# Taniwha Observability Guide

This document is the **single source of truth** for all custom OpenTelemetry spans and
telemetry metrics in Taniwha. When adding new instrumentation, follow these conventions
and update the catalogues below before touching any code.

## Quick reference

| Layer | Spans (OTel Tracer) | Metrics (`:telemetry` events) |
|---|---|---|
| HTTP / LiveView | auto-instrumented | auto-instrumented |
| Channel | `taniwha.channel.*` | `[:taniwha, :websocket, :connections]` |
| Commands | `taniwha.commands.*` | `[:taniwha, :commands, :call]` |
| Poller | `taniwha.poller.cycle` | `[:taniwha, :poller, :cycle]`, `[:taniwha, :poller, :failure]`, `[:taniwha, :torrents, :stats]` |
| RPC Client | `taniwha.rpc.call`, `taniwha.rpc.multicall` | `[:taniwha, :rpc, :call]`, `[:taniwha, :rpc, :error]` |

---

## Naming conventions

### Spans (OpenTelemetry)

Span names follow `{component}.{operation}`:

```
taniwha.rpc.call
taniwha.rpc.multicall
taniwha.poller.cycle
taniwha.commands.get_all_torrents
taniwha.commands.start
taniwha.channel.start
```

Rules:
- All lowercase
- Dots as separators (no underscores, no hyphens in the name itself)
- Component mirrors the module hierarchy: `rpc`, `poller`, `commands`, `channel`
- Operation is the function name converted to lowercase (underscores kept in operation)

### Span attributes (OpenTelemetry)

Attribute keys follow `{namespace}.{attribute}`:

```
rpc.method          # string — rtorrent method name, e.g. "d.name"
rpc.param_count     # integer — number of params in a call
rpc.call_count      # integer — number of calls in a multicall batch
rpc.transport       # string — "unix" or "tcp"
rpc.response_size   # integer — byte size of the response term (inspect)
rpc.error_reason    # string — reason when span status is error

poller.torrent_count  # integer — number of torrents fetched in this cycle
poller.diff_count     # integer — number of diffs produced
poller.interval_ms    # integer — configured poll interval
poller.error_reason   # string — reason when span status is error

torrent.hash        # string — info-hash of the torrent

channel.topic       # string — Phoenix channel topic, e.g. "torrents:list"
channel.event       # string — client event name, e.g. "start"

command.name        # string — function name, e.g. "start", "get_all_torrents"
```

Rules:
- All lowercase
- Dots as separators
- Namespace matches the span component (e.g., `rpc.*` inside `taniwha.rpc.*` spans)
- Include `torrent.hash` on every span that operates on a specific torrent

### Telemetry events (`:telemetry` / `Telemetry.Metrics`)

Event names are lists of atoms following `[:taniwha, :component, :event]`:

```elixir
[:taniwha, :rpc, :call]               # measurements: %{duration_ms: ms, response_size: bytes}
[:taniwha, :rpc, :error]              # measurements: %{count: 1}; metadata: %{error_type: str}
[:taniwha, :poller, :cycle]           # measurements: %{duration_ms: ms, torrent_count: n, diff_count: n}
[:taniwha, :poller, :failure]         # measurements: %{count: 1}
[:taniwha, :commands, :call]          # measurements: %{count: 1}; metadata: %{command_name: str}
[:taniwha, :torrents, :stats]         # measurements: %{active: n, total: n, download_speed: n, upload_speed: n}
[:taniwha, :websocket, :connections]  # measurements: %{delta: +1 or -1}
```

Rules:
- All atoms, lowercase, underscores within a segment are fine
- Three segments: `[:taniwha, :component, :event]`
- See `Taniwha.Telemetry.Metrics` for the public functions that emit these events

### Telemetry metric names (`Telemetry.Metrics`)

When defining `Telemetry.Metrics` specs the `name` option uses dot-notation strings:

```
"taniwha.rpc.call.duration_ms"
"taniwha.rpc.call.response_size"
"taniwha.rpc.errors.total"
"taniwha.poller.cycle.duration_ms"
"taniwha.poller.cycle.torrent_count"
"taniwha.poller.failures.total"
"taniwha.commands.calls.total"
"taniwha.torrents.active"
"taniwha.torrents.total"
"taniwha.torrents.download_speed"
"taniwha.torrents.upload_speed"
"taniwha.websocket.connections"
```

---

## Span catalogue

| Span name | Layer | Module | Key attributes | Typical parent |
|---|---|---|---|---|
| `taniwha.rpc.call` | RPC | `Taniwha.RPC.Client` | `rpc.method`, `rpc.param_count`, `rpc.transport`, `rpc.response_size` | `taniwha.commands.*` or `taniwha.poller.cycle` |
| `taniwha.rpc.multicall` | RPC | `Taniwha.RPC.Client` | `rpc.call_count`, `rpc.transport`, `rpc.response_size` | `taniwha.commands.*` or `taniwha.poller.cycle` |
| `taniwha.poller.cycle` | State | `Taniwha.State.Poller` | `poller.torrent_count`, `poller.diff_count`, `poller.interval_ms` | (root — timer-driven) |
| `taniwha.commands.get_all_torrents` | Domain | `Taniwha.Commands` | `command.name` | HTTP span, `taniwha.poller.cycle` |
| `taniwha.commands.get_torrent` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | HTTP span |
| `taniwha.commands.start` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | `taniwha.channel.start` |
| `taniwha.commands.stop` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | `taniwha.channel.stop` |
| `taniwha.commands.erase` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | `taniwha.channel.remove` |
| `taniwha.commands.pause` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | — |
| `taniwha.commands.resume` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | — |
| `taniwha.commands.load_url` | Domain | `Taniwha.Commands` | `command.name` | HTTP span |
| `taniwha.commands.load_raw` | Domain | `Taniwha.Commands` | `command.name` | HTTP span |
| `taniwha.commands.list_files` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | — |
| `taniwha.commands.list_peers` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | — |
| `taniwha.commands.list_trackers` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | — |
| `taniwha.commands.set_file_priority` | Domain | `Taniwha.Commands` | `command.name`, `torrent.hash` | `taniwha.channel.set_file_priority` |
| `taniwha.channel.start` | Channel | `TaniwhaWeb.TorrentChannel` | `channel.topic`, `channel.event`, `torrent.hash` | HTTP upgrade (auto) |
| `taniwha.channel.stop` | Channel | `TaniwhaWeb.TorrentChannel` | `channel.topic`, `channel.event`, `torrent.hash` | HTTP upgrade (auto) |
| `taniwha.channel.remove` | Channel | `TaniwhaWeb.TorrentChannel` | `channel.topic`, `channel.event`, `torrent.hash` | HTTP upgrade (auto) |
| `taniwha.channel.set_file_priority` | Channel | `TaniwhaWeb.TorrentChannel` | `channel.topic`, `channel.event`, `torrent.hash` | HTTP upgrade (auto) |

### Span hierarchy example

A WebSocket `"start"` command produces this trace:

```
[auto] HTTP upgrade
  taniwha.channel.start            (channel.topic, channel.event, torrent.hash)
    taniwha.commands.start         (command.name, torrent.hash)
      taniwha.rpc.call             (rpc.method="d.start", rpc.transport, rpc.response_size)
```

A poll cycle produces:

```
taniwha.poller.cycle               (poller.torrent_count, poller.diff_count, poller.interval_ms)
  taniwha.commands.get_all_torrents
    taniwha.rpc.call               (rpc.method="download_list")
    taniwha.rpc.multicall          (rpc.call_count, rpc.transport)
```

---

## Metric catalogue

All metrics are emitted as `:telemetry` events and defined as `Telemetry.Metrics` specs in
`Taniwha.Telemetry.Metrics.metrics/0`. Reporters (e.g., Prometheus, LiveDashboard) attach
to these event names.

### Distributions (histograms)

| Metric name | Event | Measurement | Labels |
|---|---|---|---|
| `taniwha.rpc.call.duration_ms` | `[:taniwha, :rpc, :call]` | `:duration_ms` | `rpc_method` |
| `taniwha.poller.cycle.duration_ms` | `[:taniwha, :poller, :cycle]` | `:duration_ms` | — |

### Last-value (gauges)

| Metric name | Event | Measurement | Labels |
|---|---|---|---|
| `taniwha.torrents.active` | `[:taniwha, :torrents, :stats]` | `:active` | — |
| `taniwha.torrents.total` | `[:taniwha, :torrents, :stats]` | `:total` | — |
| `taniwha.torrents.download_speed` | `[:taniwha, :torrents, :stats]` | `:download_speed` | — |
| `taniwha.torrents.upload_speed` | `[:taniwha, :torrents, :stats]` | `:upload_speed` | — |
| `taniwha.poller.cycle.torrent_count` | `[:taniwha, :poller, :cycle]` | `:torrent_count` | — |

### Counters (sums)

| Metric name | Event | Measurement | Labels |
|---|---|---|---|
| `taniwha.rpc.errors.total` | `[:taniwha, :rpc, :error]` | `:count` | `error_type` |
| `taniwha.poller.failures.total` | `[:taniwha, :poller, :failure]` | `:count` | — |
| `taniwha.commands.calls.total` | `[:taniwha, :commands, :call]` | `:count` | `command_name` |
| `taniwha.websocket.connections` | `[:taniwha, :websocket, :connections]` | `:delta` | — |

---

## Context propagation across GenServer calls

OTel context is stored per-process. When a plain module calls a GenServer, the context
does **not** propagate automatically. The following pattern is used in
`Taniwha.RPC.Client` to carry the caller's span context into `handle_call`:

```elixir
# In the public API function (runs in caller's process):
def call(method, params) do
  ctx = :otel_ctx.get_current()
  GenServer.call(__MODULE__, {:call, method, params, ctx}, :infinity)
end

# In the GenServer callback (runs in the GenServer's process):
def handle_call({:call, method, params, ctx}, _from, state) do
  token = :otel_ctx.attach(ctx)

  result =
    Tracer.with_span "taniwha.rpc.call", %{attributes: %{...}} do
      do_request(...)
    end

  :otel_ctx.detach(token)
  {:reply, result, state}
end
```

Key points:
- Only the **context token** is passed in the message — not the span itself.
- Always call `detach/1` to restore the previous context (use `try/after` in production code).
- `Taniwha.Commands` is a plain module, not a GenServer, so its spans inherit the
  caller's context automatically — no explicit propagation needed there.

---

## How to add new instrumentation

### Adding a new span

1. Update this document's span catalogue first.
2. Add `require OpenTelemetry.Tracer, as: Tracer` to the module.
3. Wrap the function body:
   ```elixir
   Tracer.with_span "taniwha.component.operation", %{attributes: %{...}} do
     # original work
   end
   ```
4. If the function is inside a GenServer `handle_call`, use the context-propagation
   pattern above (pass `ctx` in the message).
5. On error paths, call:
   ```elixir
   Tracer.set_status(:error, inspect(reason))
   ```
6. Write tests using `Taniwha.OtelTestHelper.assert_span/2`.

### Adding a new metric

1. Update this document's metric catalogue first.
2. Add the `:telemetry.execute/3` call in the right place using the update function
   from `Taniwha.Telemetry.Metrics`:
   ```elixir
   Taniwha.Telemetry.Metrics.record_rpc_call(method, duration_ms)
   ```
3. Add the metric definition to `Taniwha.Telemetry.Metrics.metrics/0`.
4. Add the public update function to `Taniwha.Telemetry.Metrics` and its `@spec`.
5. Write a test that attaches a `:telemetry` handler, calls the function under test,
   and asserts the event was received.
