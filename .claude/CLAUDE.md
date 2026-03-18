# Project Taniwha

Is a Phoenix application that wraps rtorrent's SCGI/XML-RPC interface behind a modern WebSocket API (Phoenix Channels) and ships with a polished LiveView reference UI. It enables any client — web, mobile, or desktop — to monitor and control an rtorrent instance in real time.

## Goals

- Real-time torrent status pushed to all connected clients via Phoenix Channels
- Full torrent lifecycle management (add, remove, start, stop, prioritise files)
- Token-based authentication (JWT) for the WebSocket API
- Support both Unix socket and TCP connections to rtorrent
- A polished LiveView dashboard as the reference client
- Clean separation between transport, state, and API layers so each can be tested and evolved independently

## Non-goals (for v1)

- Multi-instance / multi-user support (single rtorrent instance)
- Persistent database (all state lives in rtorrent + ETS cache)
- RSS feed management (can be added later)

When working on Taniwha, add 🖋️ to STARTER_CHARACTER emojis. Make sure there's a space between any emojis and the text.

## Tech stack

| Layer | Technology | Version |
|---|---|---|
| Language | Elixir | 1.19+ |
| Runtime | OTP | 27+ |
| Web framework | Phoenix (Channels + LiveView) | 1.8.5 |
| Auth | Guardian (JWT) | latest |
| XML parsing | SweetXml or xmerl (built-in) | — |
| State cache | ETS | (OTP built-in) |
| Realtime broadcast | Phoenix.PubSub | (bundled) |
| CSS | Tailwind CSS | (Phoenix default) |
| Linting | Credo | latest |
| Static analysis | Dialyxir | latest |
| Testing | ExUnit + Mox | — |
| Container | Docker (multi-stage build) | — |
| CI/CD | GitHub Actions → GHCR → SSH deploy | — |

## Project structure

```
taniwha/
├── lib/
│   ├── taniwha/                  # Core application logic
│   │   ├── application.ex        # Supervision tree
│   │   ├── auth.ex               # JWT auth (Guardian)
│   │   ├── commands.ex           # High-level rtorrent command API
│   │   ├── torrent.ex            # Torrent struct + helpers
│   │   ├── torrent_file.ex       # TorrentFile struct
│   │   ├── scgi/                 # SCGI transport layer
│   │   │   ├── connection.ex     # Behaviour definition
│   │   │   ├── unix_connection.ex
│   │   │   ├── tcp_connection.ex
│   │   │   └── protocol.ex      # SCGI framing
│   │   ├── xmlrpc.ex             # XML-RPC codec
│   │   ├── rpc/
│   │   │   └── client.ex        # GenServer RPC client
│   │   └── state/
│   │       ├── store.ex          # ETS cache
│   │       └── poller.ex         # Periodic diff engine
│   └── taniwha_web/              # Phoenix web layer
│       ├── endpoint.ex
│       ├── router.ex
│       ├── user_socket.ex
│       ├── channels/
│       ├── controllers/
│       ├── plugs/
│       ├── live/
│       └── components/
├── test/                         # Mirrors lib/ structure
├── config/
├── .github/workflows/            # CI + CD pipelines
├── Dockerfile
├── docker-compose.yml            # Dev environment
└── mix.exs
```

## Architecture reference

See `docs/architecture-design.md` for the full architecture design document including supervision tree, layer breakdown, RPC command reference, and testing strategy.

## Work process

- Commit often.
- Use conventional commits (feat:, fix:, refactor:, test:, docs:, chore:).
- Do not mention AI authoring in commit messages.
- Always write tests before writing code (TDD).
- When writing tests, do not write all tests at once. Write a small batch of related tests, then the code to make them green. Repeat. Red-green-refactor.
- After completing each roadmap subsection, run the full test suite and fix any regressions before moving on.

## Code quality

- Follow Elixir community conventions (`mix format`, Credo, Dialyzer).
- Use `@moduledoc` and `@doc` on all public modules and functions.
- Use typespecs (`@spec`) on all public functions.
- `Taniwha.Commands` is the only public API for interacting with rtorrent. State and API layers must go through Commands, never calling `Taniwha.RPC.Client` directly.
- Use PubSub for all cross-layer communication (State → API). No direct function calls from the state layer into the web layer.

## Accessibility

- Accessibility is a first-class concern from the start.
- All public-facing HTML output must target WCAG 2.2 AA compliance.
- Use semantic HTML5 elements, proper heading hierarchy, ARIA landmarks.
- axe-core will be added to the test pipeline when LiveView UI work begins (Phase 5).

## Key conventions

- Module names: `Taniwha.*` for core, `TaniwhaWeb.*` for web layer.
- Config: transport config uses tagged tuples `{:unix, path}` or `{:tcp, host, port}`.
- PubSub topics: `"torrents:list"` for list-level diffs, `"torrents:{hash}"` for per-torrent updates.
- Channel protocol: clients send commands (`start`, `stop`, `remove`, `set_file_priority`), server pushes `diffs` and `updated` events.
- All RPC calls go through `Taniwha.Commands` — never call `Taniwha.RPC.Client` from outside the domain layer.