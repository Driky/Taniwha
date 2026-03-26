# Taniwha

A Phoenix application that wraps rtorrent's SCGI/XML-RPC interface behind a modern WebSocket API (Phoenix Channels) and a polished LiveView reference UI. Any client — web, mobile, desktop — can monitor and control an rtorrent instance in real time.

## Features

- Real-time torrent status pushed to all clients via Phoenix Channels
- Full torrent lifecycle management (add, start, stop, remove, set file priority)
- JWT-based authentication for the WebSocket API and REST endpoints
- Unix socket and TCP connections to rtorrent
- LiveView dashboard as the reference client
- Rate limiting on auth endpoint (brute-force prevention) and WebSocket commands
- Health check endpoint for load balancers and monitoring
- Structured logging with OpenTelemetry trace correlation
- Custom OTel spans, metrics, and exception tracking

## Quick start (Docker)

```bash
docker compose up
```

The app is available at `http://localhost:4000`.

For production deployment see [`docs/server-setup.md`](docs/server-setup.md).

## Development

```bash
# Install dependencies and set up the database (if any)
mix setup

# Start Phoenix with a REPL
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000).

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | **yes** (prod) | — | Phoenix session signing key (`mix phx.gen.secret`) |
| `PHX_HOST` | **yes** (prod) | — | Public hostname, e.g. `example.com` |
| `TANIWHA_API_KEY` | **yes** (prod) | — | API key exchanged for JWT tokens |
| `PORT` | no | `4000` | HTTP listen port |
| `RTORRENT_SOCKET` | no | `/var/run/rtorrent.sock` | Path to rtorrent SCGI Unix socket |
| `OTEL_SERVICE_NAME` | no | `taniwha` | Service name in traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | no | `http://localhost:4318` | OTLP collector URL |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | no | `http_protobuf` | `http_protobuf` or `grpc` |
| `OTEL_EXPORTER_OTLP_HEADERS` | no | — | Auth headers, e.g. `signoz-ingestion-key=<key>` |
| `OTEL_TRACES_SAMPLER` | no | `parentbased_always_on` | Set `always_off` to disable tracing |

## Health check

```
GET /health
```

Always returns HTTP 200. The `rtorrent` field reflects actual connectivity:

```json
{"status": "ok", "rtorrent": "connected"}
{"status": "ok", "rtorrent": "disconnected"}
```

## Tests

```bash
# Full unit + component test suite
mix test

# With coverage report
mix test --cover

# Full quality suite (CI gates)
mix format --check-formatted && mix credo --strict && mix dialyzer && mix test
```

> **Note:** Integration tests (`mix test --only integration`) require a live rtorrent instance and are tracked separately in Task 6.5.

## Documentation

- [`docs/architecture-design.md`](docs/architecture-design.md) — Layer breakdown, supervision tree, RPC command reference
- [`docs/websocket-api.md`](docs/websocket-api.md) — WebSocket protocol, topics, events, REST API
- [`docs/observability.md`](docs/observability.md) — OTel spans, metrics, logging, backend configuration
- [`docs/server-setup.md`](docs/server-setup.md) — Production deployment, Docker, systemd, OTEL setup
