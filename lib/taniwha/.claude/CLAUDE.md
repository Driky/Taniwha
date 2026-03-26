# lib/taniwha/ — Core application logic

This directory contains all non-web business logic for Taniwha.

## Layer map (dependency flows downward)

```
commands.ex          ← The public API for the rest of the app
    ↓
rpc/client.ex        ← GenServer dispatching RPC calls
    ↓
xmlrpc.ex            ← XML-RPC encode/decode
scgi/protocol.ex     ← SCGI framing
scgi/*_connection.ex ← Socket I/O (Unix or TCP)
```

```
state/poller.ex      ← Polls via Commands, diffs, broadcasts
    ↓
state/store.ex       ← ETS cache (read by web layer directly)
```

## Key rules

- `commands.ex` is the **only public API** for rtorrent interaction. Nothing outside `lib/taniwha/` should call `Taniwha.RPC.Client` directly.
- `state/store.ex` owns the ETS table. Other processes read it directly (`:public` table with `read_concurrency: true`) but only the Store and Poller write to it.
- `state/poller.ex` broadcasts diffs over `Phoenix.PubSub` (topic `"torrents:list"` and `"torrents:{hash}"`). The web layer subscribes — no direct calls from state into web.
- `scgi/connection.ex` defines a **behaviour**. `unix_connection.ex` and `tcp_connection.ex` are implementations. Tests use Mox to mock the behaviour.

## Module quick reference

| Module | Type | Purpose |
|---|---|---|
| `Taniwha.Application` | Supervisor | Starts supervision tree |
| `Taniwha.Auth` | Module (Guardian) | JWT encode/decode/verify |
| `Taniwha.Commands` | Module | High-level rtorrent command API |
| `Taniwha.Torrent` | Struct | Torrent data with helpers (e.g., `progress/1`) |
| `Taniwha.TorrentFile` | Struct | Per-file data within a torrent |
| `Taniwha.SCGI.Connection` | Behaviour | Socket connection contract |
| `Taniwha.SCGI.UnixConnection` | Impl | Unix domain socket |
| `Taniwha.SCGI.TcpConnection` | Impl | TCP socket |
| `Taniwha.SCGI.Protocol` | Module | SCGI framing (encode/decode) |
| `Taniwha.XMLRPC` | Module | XML-RPC codec |
| `Taniwha.RateLimiter` | GenServer | ETS-backed sliding-window rate limiter |
| `Taniwha.RPC.Client` | GenServer | Sends RPC calls over SCGI transport |
| `Taniwha.State.Store` | GenServer | ETS table owner |
| `Taniwha.State.Poller` | GenServer | Periodic poll + diff + broadcast |

## Testing approach

- SCGI.Protocol and XMLRPC: pure function tests with known inputs/outputs.
- RPC.Client: Mox mock of SCGI.Connection behaviour.
- Commands: Mox mock of RPC.Client (or a behaviour wrapper).
- State.Poller: mock Commands, verify ETS writes and PubSub broadcasts.
- State.Store: direct ETS assertions.