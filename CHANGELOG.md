# Changelog

All notable changes to Taniwha are documented here.

## [1.0.0] — 2026-03-26

### Added

**Phase 1 — Project scaffolding**
- Phoenix 1.8.5 application with Bandit HTTP adapter
- Multi-stage Dockerfile and Docker Compose dev environment
- GitHub Actions CI (format, Credo, Dialyzer, tests) and CD (GHCR → SSH deploy)
- Server setup script (`deploy/setup-server.sh`) and systemd unit

**Phase 2 — SCGI/XML-RPC transport**
- `Taniwha.SCGI.Protocol` — SCGI framing (encode/decode)
- `Taniwha.SCGI.UnixConnection` and `Taniwha.SCGI.TcpConnection` — socket I/O
- `Taniwha.XMLRPC` — XML-RPC codec (encode/decode, including `system.multicall`)
- `Taniwha.RPC.Client` — GenServer dispatching RPC calls with exponential-backoff retry

**Phase 3 — Domain layer**
- `Taniwha.Commands` — high-level rtorrent command API (the only public entry point for rtorrent interaction)
- `Taniwha.Torrent`, `Taniwha.TorrentFile`, `Taniwha.Peer`, `Taniwha.Tracker` — domain structs
- `Taniwha.Auth` — JWT token exchange via Guardian

**Phase 4 — State layer**
- `Taniwha.State.Store` — ETS-backed torrent state cache
- `Taniwha.State.Poller` — periodic diff engine broadcasting via Phoenix.PubSub

**Phase 5 — Web layer**
- `TaniwhaWeb.TorrentChannel` — Phoenix Channel for real-time torrent data
- `TaniwhaWeb.API.AuthController` — `POST /api/v1/auth/token`
- `TaniwhaWeb.API.TorrentController` — REST snapshot endpoints
- `TaniwhaWeb.Plugs.AuthenticateToken` — Bearer JWT plug
- LiveView dashboard, torrent detail, add torrent modal, settings views
- WCAG 2.2 AA accessibility baseline

**Phase 6 — Observability, resilience, and release hardening**
- OpenTelemetry traces, metrics, and exception tracking across all layers
- Structured logging with trace/span ID correlation on every log entry
- Error handling with exponential-backoff retry in `Taniwha.RPC.Client`
- `Taniwha.RateLimiter` — ETS-backed sliding-window rate limiter
- `TaniwhaWeb.Plugs.RateLimit` — 429 Too Many Requests on brute-force auth attempts (10 req / 60 s per IP)
- Channel rate limiting — 500 ms minimum interval between commands per socket
- `Taniwha.Commands.system_pid/0` — rtorrent connectivity probe
- `TaniwhaWeb.HealthController` — unauthenticated `GET /health` endpoint for load balancers
- Startup validation: warns on missing rtorrent socket path and unset OTEL endpoint
- `docs/observability.md` — OTel catalogue, backend configuration, log correlation guide
- `docs/server-setup.md` — OTEL configuration section
- Full unit and component test suite (no external dependencies required)

### Pending

- Integration tests (`mix test --only integration`) require a live rtorrent instance — tracked in Task 6.5
