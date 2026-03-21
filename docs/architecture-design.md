# Taniwha — Architecture Design Document

**An Elixir/Phoenix WebSocket API for controlling rtorrent**

---

## 1. Project overview

Taniwha is a Phoenix application that wraps rtorrent's SCGI/XML-RPC interface behind a modern WebSocket API (Phoenix Channels) and ships with a polished LiveView reference UI. It enables any client — web, mobile, or desktop — to monitor and control an rtorrent instance in real time.

### Goals

- Real-time torrent status pushed to all connected clients via Phoenix Channels
- Full torrent lifecycle management (add, remove, start, stop, prioritise files)
- Token-based authentication (JWT) for the WebSocket API
- Support both Unix socket and TCP connections to rtorrent
- A polished LiveView dashboard as the reference client
- Clean separation between transport, state, and API layers so each can be tested and evolved independently

### Non-goals (for v1)

- Multi-instance / multi-user support (single rtorrent instance)
- Persistent database (all state lives in rtorrent + ETS cache)
- RSS feed management (can be added later)

---

## 2. Technology stack

| Layer | Technology | Version |
|---|---|---|
| Language | Elixir | 1.19+ |
| Runtime | OTP | 27+ |
| Web framework | Phoenix (Channels + LiveView) | 1.8.5 |
| Auth | Guardian (JWT) | latest |
| XML parsing | SweetXml or xmerl (built-in) | — |
| State cache | ETS | (OTP built-in) |
| Realtime broadcast | Phoenix.PubSub | (bundled with Phoenix) |
| CSS | Tailwind CSS | (Phoenix default) |
| Linting | Credo | latest |
| Static analysis | Dialyxir (Dialyzer) | latest |
| Testing | ExUnit + Mox | (OTP built-in + latest) |
| Containerisation | Docker (multi-stage build) | — |
| CI/CD | GitHub Actions → GHCR → SSH pull | — |

---

## 3. Supervision tree

```
Taniwha.Application
├── Taniwha.State.Store            # ETS table owner (GenServer)
├── Taniwha.RPC.Client             # SCGI/XML-RPC command dispatch (GenServer)
├── Taniwha.State.Poller           # Periodic polling + diff engine (GenServer)
├── TaniwhaWeb.Endpoint            # Phoenix endpoint
│   ├── Phoenix.PubSub             # Broadcast infrastructure (name: Taniwha.PubSub)
│   └── TaniwhaWeb.UserSocket      # WebSocket entry point
└── Taniwha.Auth.TokenManager      # API key / JWT config
```

**Startup order matters:** Store must start before Poller (ETS table must exist). RPC.Client must start before Poller (Poller calls RPC). The order in the supervisor child list enforces this naturally via `one_for_one` strategy.

---

## 4. Layer breakdown

The application is organised into five layers, each with a single responsibility. Dependencies flow downward only — upper layers depend on lower layers, never the reverse.

```
┌─────────────────────────────────┐
│  Clients (LiveView, WebSocket,  │
│  native apps)                   │
├─────────────────────────────────┤
│  API Layer (TaniwhaWeb)         │  Phoenix Channels, LiveView, REST
├─────────────────────────────────┤
│  State Layer (Taniwha.State)    │  Poller, ETS Store, PubSub diffs
├─────────────────────────────────┤
│  Domain Layer (Taniwha)         │  Commands, Torrent struct, types
├─────────────────────────────────┤
│  RPC Layer (Taniwha.RPC)        │  GenServer client, multicall
├─────────────────────────────────┤
│  Transport Layer (Taniwha.SCGI  │  SCGI framing, XML-RPC codec,
│  + Taniwha.XMLRPC)              │  Unix/TCP socket connections
└─────────────────────────────────┘
```

---

## 5. Transport layer

**Module:** `Taniwha.SCGI` + `Taniwha.XMLRPC`

**Role:** Handles raw communication with rtorrent. Knows nothing about torrents — just sends XML-RPC method calls over SCGI-framed socket connections and returns decoded responses.

### 5.1 Connection behaviour

```elixir
defmodule Taniwha.SCGI.Connection do
  @moduledoc """
  Behaviour for SCGI socket connections.
  Supports Unix domain sockets and TCP.
  """

  @type transport_config ::
    {:unix, path :: String.t()} |
    {:tcp, host :: String.t(), port :: non_neg_integer()}

  @callback connect(transport_config()) :: {:ok, port()} | {:error, term()}
  @callback send_request(port(), binary()) :: :ok | {:error, term()}
  @callback receive_response(port(), timeout()) :: {:ok, binary()} | {:error, term()}
  @callback close(port()) :: :ok
end
```

**Implementations:**
- `Taniwha.SCGI.UnixConnection` — connects via `:gen_tcp` with `{:local, path}` to a Unix domain socket
- `Taniwha.SCGI.TcpConnection` — connects via `:gen_tcp` to a TCP host:port

### 5.2 SCGI protocol module

**Module:** `Taniwha.SCGI.Protocol`

**Interface:**
- `encode(xml_body :: binary()) :: binary()` — wraps an XML-RPC body in SCGI framing (netstring-encoded headers + body)
- `decode_response(raw :: binary()) :: {:ok, binary()} | {:error, :invalid_response}` — strips SCGI response headers, returns the XML body

**SCGI framing algorithm:**
1. Build headers as NUL-delimited key-value pairs: `CONTENT_LENGTH<NUL>{body_length}<NUL>SCGI<NUL>1<NUL>REQUEST_METHOD<NUL>POST<NUL>REQUEST_URI<NUL>/RPC2<NUL>`
2. Netstring-encode: `{header_byte_size}:{headers},`
3. Append the XML-RPC body
4. Send in one write to the socket

**Response parsing:** Read until socket closes. Split on `\r\n\r\n` — everything after the first blank line is the XML-RPC response body.

### 5.3 XML-RPC codec

**Module:** `Taniwha.XMLRPC`

**Interface:**
- `encode_call(method :: String.t(), params :: [term()]) :: binary()` — builds an XML-RPC `<methodCall>` document
- `encode_multicall(calls :: [{String.t(), [term()]}]) :: binary()` — builds a `system.multicall` request
- `decode_response(xml :: binary()) :: {:ok, term()} | {:error, term()}` — parses XML-RPC response, extracting typed values from `<string>`, `<i8>`, `<i4>`, `<array>`, `<struct>` nodes

**Parameter encoding:**
- Elixir strings → `<string>`
- Elixir integers → `<i8>`
- Elixir lists → `<array>`
- Elixir maps → `<struct>`

**Note:** rtorrent appears to accept everything as strings, but we should encode with proper types for correctness.

---

## 6. RPC layer

**Module:** `Taniwha.RPC.Client`

**Role:** A GenServer that provides `call/2` and `multicall/1`. Opens a fresh socket connection per command (rtorrent doesn't support pipelining on a single connection), encodes via the XML-RPC codec, sends over SCGI transport, and decodes the response.

**Interface:**
```elixir
@spec call(method :: String.t(), params :: [term()]) :: {:ok, term()} | {:error, term()}
@spec multicall(calls :: [{String.t(), [term()]}]) :: {:ok, [term()]} | {:error, term()}
```

**Behaviour:**
- Each `call/2` opens a new socket, sends, receives, closes. This matches rtorrent's connection model.
- `multicall/1` uses `system.multicall` to batch multiple RPC calls in a single socket round-trip. This is critical for the poller — instead of N connections to fetch N torrents' details, one multicall handles everything.
- The transport config (Unix socket path or TCP host:port) is read from application config.
- Timeout is configurable (default: 5000ms).

**Dependencies:** `Taniwha.SCGI.Protocol`, `Taniwha.XMLRPC`, a module implementing `Taniwha.SCGI.Connection`

---

## 7. Domain layer

**Modules:** `Taniwha.Torrent`, `Taniwha.TorrentFile`, `Taniwha.Commands`

### 7.1 Torrent struct

```elixir
defmodule Taniwha.Torrent do
  @type t :: %__MODULE__{
    hash: String.t(),
    name: String.t(),
    size_bytes: non_neg_integer(),
    completed_bytes: non_neg_integer(),
    up_rate: non_neg_integer(),
    down_rate: non_neg_integer(),
    ratio: float(),
    state: :stopped | :started,
    is_active: boolean(),
    is_hash_checking: boolean(),
    complete: boolean(),
    peers_connected: non_neg_integer(),
    timestamp_started: DateTime.t() | nil,
    timestamp_finished: DateTime.t() | nil,
    base_path: String.t() | nil,
    files: [Taniwha.TorrentFile.t()] | nil
  }
end
```

### 7.2 TorrentFile struct

```elixir
defmodule Taniwha.TorrentFile do
  @type t :: %__MODULE__{
    path: String.t(),
    size_bytes: non_neg_integer(),
    priority: 0..2,
    completed_chunks: non_neg_integer(),
    total_chunks: non_neg_integer()
  }
end
```

### 7.3 Commands module

**Module:** `Taniwha.Commands`

**Role:** High-level API mapping torrent operations to RPC calls. This is the public interface that the State and API layers use — they never call `Taniwha.RPC.Client` directly.

**Interface:**

| Function | RPC call(s) | Returns |
|---|---|---|
| `list_hashes(view \\ "")` | `download_list` | `{:ok, [String.t()]}` |
| `get_torrent(hash)` | multicall of `d.*` fields | `{:ok, Torrent.t()}` |
| `start(hash)` | `d.start` | `:ok \| {:error, term()}` |
| `stop(hash)` | `d.stop` | `:ok \| {:error, term()}` |
| `close(hash)` | `d.close` | `:ok \| {:error, term()}` |
| `erase(hash)` | `d.erase` | `:ok \| {:error, term()}` |
| `pause(hash)` | `d.pause` | `:ok \| {:error, term()}` |
| `resume(hash)` | `d.resume` | `:ok \| {:error, term()}` |
| `load_url(url)` | `load.start` | `:ok \| {:error, term()}` |
| `load_raw(binary)` | `load.raw_start` | `:ok \| {:error, term()}` |
| `list_files(hash)` | `f.multicall` | `{:ok, [TorrentFile.t()]}` |
| `set_file_priority(hash, index, priority)` | `f.priority.set` | `:ok \| {:error, term()}` |
| `global_up_rate()` | `throttle.global_up.rate` | `{:ok, non_neg_integer()}` |
| `global_down_rate()` | `throttle.global_down.rate` | `{:ok, non_neg_integer()}` |

---

## 8. State layer

**Modules:** `Taniwha.State.Store`, `Taniwha.State.Poller`

**Role:** Periodically polls rtorrent via the Commands module, diffs the results against an ETS cache, writes updates, and broadcasts diffs over PubSub so Channels and LiveView stay in sync.

### 8.1 ETS store

**Module:** `Taniwha.State.Store`

A GenServer that owns a named ETS table (`:taniwha_state`). The table is `:set`, `:public`, with `read_concurrency: true` so Channels and LiveView can read without bottlenecking through the GenServer.

**Interface:**
- `get_all_torrents() :: [Torrent.t()]`
- `get_torrent(hash) :: {:ok, Torrent.t()} | {:error, :not_found}`
- `put_torrent(Torrent.t()) :: :ok`
- `delete_torrent(hash) :: :ok`

### 8.2 Poller with diff engine

**Module:** `Taniwha.State.Poller`

A GenServer that runs on a configurable interval (default: 2000ms).

**Poll cycle:**
1. Call `Taniwha.Commands.list_hashes()` to get current hash list
2. Multicall to fetch full details for all hashes
3. Diff against ETS: compute added, removed, and updated torrents
4. Write changes to ETS
5. Broadcast diffs over PubSub

**Diff logic:** A torrent is "updated" if any of these fields changed: `up_rate`, `down_rate`, `completed_bytes`, `state`, `is_active`, `is_hash_checking`, `peers_connected`, `ratio`, `complete`.

**PubSub topics:**
- `"torrents:list"` — receives `{:torrent_diffs, [{:added | :updated, Torrent.t()} | {:removed, hash}]}`
- `"torrents:{hash}"` — receives `{:torrent_updated, Torrent.t()}`

---

## 9. API layer

**Modules:** `TaniwhaWeb.UserSocket`, `TaniwhaWeb.TorrentChannel`, `TaniwhaWeb.Router`, controllers

### 9.1 WebSocket authentication

Clients connect to the socket with a JWT token parameter. The socket verifies the token via `Taniwha.Auth` and assigns the user identity.

### 9.2 Channel protocol

**Topics:**

| Topic | Purpose | Join response |
|---|---|---|
| `torrents:list` | Subscribe to all torrent updates | `%{torrents: [...]}` — full snapshot |
| `torrents:{hash}` | Subscribe to one torrent's updates | `%{torrent: {...}}` — full detail |

**Client → Server messages:**

| Event | Payload | Description |
|---|---|---|
| `start` | `%{"hash" => hash}` | Start a torrent |
| `stop` | `%{"hash" => hash}` | Stop a torrent |
| `remove` | `%{"hash" => hash}` | Remove from rtorrent |
| `set_file_priority` | `%{"hash" => h, "index" => i, "priority" => p}` | Set file priority (0=skip, 1=normal, 2=high) |

**Server → Client pushes:**

| Event | Payload | Description |
|---|---|---|
| `diffs` | `%{diffs: [{type, data}]}` | Incremental updates |
| `updated` | `%{torrent: {...}}` | Full torrent state for detail subscribers |

### 9.3 REST endpoints

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/auth/token` | Exchange API key for JWT |
| `POST` | `/api/v1/torrents` | Add torrent (magnet URL or .torrent upload) |
| `GET` | `/api/v1/torrents` | Snapshot of all torrents |
| `GET` | `/api/v1/torrents/:hash` | Single torrent snapshot |

### 9.4 LiveView views

| View | Route | Description |
|---|---|---|
| `DashboardLive` | `/` | Torrent list, global stats, search/filter, actions |
| `TorrentDetailLive` | `/torrents/:hash` | Files, peers, trackers, speed graph |
| `AddTorrentLive` | `/add` | Magnet URL input + .torrent file upload |
| `SettingsLive` | `/settings` | API key display, connection config |

LiveView subscribes to the same PubSub topics as Channels, so both stay in sync via the same diff mechanism.

---

## 10. Authentication

**Module:** `Taniwha.Auth`

For v1, a single API key is configured at startup via environment variable. Clients exchange the API key for a short-lived JWT (1 hour TTL) via the REST endpoint. The JWT is then used for both REST requests (Authorization header) and WebSocket connections (token parameter).

Uses Guardian for JWT encoding/decoding/verification.

---

## 11. Key rtorrent RPC commands reference

| Command | Args | Returns | Notes |
|---|---|---|---|
| `download_list` | view (string, "" = main) | list of hashes | Entry point for enumeration |
| `d.name` | hash | string | Torrent display name |
| `d.size_bytes` | hash | integer | Total size |
| `d.completed_bytes` | hash | integer | Downloaded so far |
| `d.up.rate` / `d.down.rate` | hash | integer | Current speed (bytes/s) |
| `d.ratio` | hash | integer | Ratio × 1000 |
| `d.state` | hash | 0 or 1 | 1 = started |
| `d.is_active` | hash | 0 or 1 | 1 = actively transferring |
| `d.complete` | hash | 0 or 1 | 1 = download complete |
| `d.is_hash_checking` | hash | 0 or 1 | 1 = currently hash checking |
| `d.start` / `d.stop` | hash | 0 | Lifecycle control |
| `d.close` | hash | 0 | Make inactive |
| `d.erase` | hash | 0 | Remove from client (not disk) |
| `d.pause` / `d.resume` | hash | 0 | Pause/resume transfer |
| `d.peers_connected` | hash | integer | Connected peer count |
| `d.timestamp.started` | hash | integer | Unix timestamp |
| `d.timestamp.finished` | hash | integer | Unix timestamp |
| `d.base_path` | hash | string | Full path to download |
| `load.start` | "", url | 0 | Add torrent by URL and start |
| `load.raw_start` | "", binary | 0 | Add .torrent file content |
| `f.multicall` | hash, "", fields... | nested list | Per-file data |
| `f.path=` | (via f.multicall) | string | File path within torrent |
| `f.size_bytes=` | (via f.multicall) | integer | File size |
| `f.priority=` | (via f.multicall) | integer | 0=skip, 1=normal, 2=high |
| `f.completed_chunks=` | (via f.multicall) | integer | Completed chunks |
| `f.size_chunks=` | (via f.multicall) | integer | Total chunks |
| `f.priority.set` | hash:fN, priority | 0 | Set file priority |
| `system.multicall` | array of {method, params} | batched results | Critical for performance |
| `system.listMethods` | (none) | list of strings | Discover all commands |
| `throttle.global_up.rate` | (none) | integer | Global upload speed |
| `throttle.global_down.rate` | (none) | integer | Global download speed |

**Important notes:**
- `d.ratio` returns the ratio multiplied by 1000 (e.g., 1500 = 1.5x ratio)
- `f.multicall` field names must end with `=` (e.g., `f.path=`)
- `f.priority.set` takes a combined hash:file-index key (e.g., `"ABCD1234:f0"`)
- rtorrent doesn't support pipelining — each command needs its own socket connection, making `system.multicall` critical for performance

---

## 12. Testing strategy

### 12.1 Test layers

**Transport layer** — Unit test SCGI framing and XML-RPC codec with known inputs/outputs. No network required. Use fixture files for complex XML responses.

**RPC client** — Use Mox to define a mock implementing `Taniwha.SCGI.Connection`. Verify the GenServer correctly encodes calls, handles timeouts, and returns decoded responses.

**Domain layer** — Test `Taniwha.Commands` with a mocked RPC client. Verify correct RPC methods and parameter formatting for each command.

**State layer** — Test the diff engine as a pure function with known old/new state maps. Test the Poller with mocked Commands to verify ETS writes and PubSub broadcasts.

**Channel layer** — Use `Phoenix.ChannelTest` to verify join responses, push/reply semantics, and PubSub forwarding. Mock the Commands module for command handling.

**REST layer** — Standard Phoenix controller tests with `ConnTest`. Mock Commands for torrent operations.

**LiveView** — Use `Phoenix.LiveViewTest` for mount, event handling, and PubSub-driven updates. Mock Commands.

### 12.2 Integration tests

A Docker Compose setup running a real rtorrent instance with a known `.rtorrent.rc` enabling the SCGI socket. Run the full poll → diff → broadcast → channel pipeline against it.

### 12.3 Static analysis

- `mix format --check-formatted` — code formatting
- `mix credo --strict` — linting and code quality
- `mix dialyzer` (via Dialyxir) — type checking

All three run in CI and must pass for a green build.

---

## 13. Project structure

```
taniwha/
├── .github/
│   └── workflows/
│       ├── ci.yml                     # Lint + test + build
│       └── cd.yml                     # Deploy on main
├── lib/
│   ├── taniwha/
│   │   ├── application.ex             # Supervision tree
│   │   ├── auth.ex                    # Guardian + JWT logic
│   │   ├── commands.ex                # High-level rtorrent commands
│   │   ├── torrent.ex                 # Torrent struct + helpers
│   │   ├── torrent_file.ex            # TorrentFile struct
│   │   ├── scgi/
│   │   │   ├── connection.ex          # Behaviour definition
│   │   │   ├── unix_connection.ex     # Unix socket implementation
│   │   │   ├── tcp_connection.ex      # TCP implementation
│   │   │   └── protocol.ex           # SCGI framing encode/decode
│   │   ├── xmlrpc.ex                  # XML-RPC codec
│   │   ├── rpc/
│   │   │   └── client.ex             # GenServer RPC client
│   │   └── state/
│   │       ├── store.ex              # ETS wrapper GenServer
│   │       └── poller.ex             # Periodic diff poller
│   └── taniwha_web/
│       ├── endpoint.ex
│       ├── router.ex
│       ├── user_socket.ex
│       ├── channels/
│       │   └── torrent_channel.ex
│       ├── controllers/
│       │   ├── auth_controller.ex
│       │   ├── auth_json.ex
│       │   ├── torrent_controller.ex
│       │   └── torrent_json.ex
│       ├── plugs/
│       │   └── authenticate_token.ex
│       ├── live/
│       │   ├── dashboard_live.ex
│       │   ├── dashboard_live.html.heex
│       │   ├── torrent_detail_live.ex
│       │   ├── torrent_detail_live.html.heex
│       │   ├── add_torrent_live.ex
│       │   ├── add_torrent_live.html.heex
│       │   ├── settings_live.ex
│       │   └── settings_live.html.heex
│       └── components/
│           ├── core_components.ex
│           ├── torrent_components.ex
│           └── layouts/
│               ├── root.html.heex
│               └── app.html.heex
├── test/
│   ├── taniwha/
│   │   ├── scgi/
│   │   │   └── protocol_test.exs
│   │   ├── xmlrpc_test.exs
│   │   ├── rpc/
│   │   │   └── client_test.exs
│   │   ├── commands_test.exs
│   │   └── state/
│   │       ├── store_test.exs
│   │       └── poller_test.exs
│   ├── taniwha_web/
│   │   ├── channels/
│   │   │   └── torrent_channel_test.exs
│   │   └── controllers/
│   │       ├── auth_controller_test.exs
│   │       └── torrent_controller_test.exs
│   └── support/
│       ├── fixtures.ex                # Sample XML-RPC responses
│       ├── mock_connection.ex         # Mock SCGI transport (Mox)
│       └── channel_case.ex
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── Dockerfile
├── docker-compose.yml                 # Dev environment (rtorrent + taniwha)
├── .formatter.exs
├── .credo.exs
├── CLAUDE.md
└── mix.exs
```

---

## 14. Configuration reference

```elixir
# config/config.exs
config :taniwha,
  rtorrent_transport: {:unix, "/var/run/rtorrent/rpc.socket"},
  poll_interval: 2_000,
  rpc_timeout: 5_000

# config/runtime.exs
config :taniwha,
  rtorrent_transport:
    if System.get_env("RTORRENT_SOCKET") do
      {:unix, System.get_env("RTORRENT_SOCKET")}
    else
      {:tcp,
       System.get_env("RTORRENT_HOST", "127.0.0.1"),
       String.to_integer(System.get_env("RTORRENT_PORT", "5000"))}
    end,
  api_key: System.get_env("TANIWHA_API_KEY")
```

**Environment variables:**

| Variable | Required | Default | Description |
|---|---|---|---|
| `RTORRENT_SOCKET` | no | — | Path to rtorrent Unix socket (takes priority over TCP) |
| `RTORRENT_HOST` | no | `127.0.0.1` | rtorrent TCP host (used when no socket path) |
| `RTORRENT_PORT` | no | `5000` | rtorrent TCP port |
| `TANIWHA_API_KEY` | yes (prod) | — | API key for JWT exchange |
| `SECRET_KEY_BASE` | yes (prod) | — | Phoenix secret |
| `PHX_HOST` | yes (prod) | — | Public hostname |
| `PORT` | no | `4000` | HTTP listen port |

---

## 15. Deployment architecture

**Production deployment:** Docker image built via multi-stage Dockerfile, pushed to GitHub Container Registry (ghcr.io), pulled to an Ubuntu server via SSH. rtorrent runs on the same machine — its Unix socket is mounted into the container as a volume.

```
┌─────────────────────────────────────────┐
│  Ubuntu Server                          │
│                                         │
│  ┌──────────────┐   ┌───────────────┐   │
│  │  rtorrent    │   │  Taniwha      │   │
│  │              │   │  (Docker)     │   │
│  │  rpc.socket ─┼───┼→ /rpc.socket  │   │
│  │              │   │  :4000        │   │
│  └──────────────┘   └───────────────┘   │
│                          ↑              │
│                     docker run          │
│                     -v /path/to/rpc.socket:/rpc.socket │
│                     -p 4000:4000        │
└─────────────────────────────────────────┘
```
