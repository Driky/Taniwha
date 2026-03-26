# lib/taniwha_web/ — Phoenix web layer

This directory contains all HTTP/WebSocket-facing code: Channels, LiveView, REST controllers, and plugs.

## Architecture role

The web layer is a **consumer** of the core layer. It reads state from `Taniwha.State.Store` (ETS) and subscribes to PubSub topics for real-time updates. For commands (start, stop, add torrent), it calls `Taniwha.Commands` — never `Taniwha.RPC.Client`.

## Real-time data flow

```
Taniwha.State.Poller
    → broadcasts {:torrent_diffs, diffs} on PubSub "torrents:list"
    → broadcasts {:torrent_updated, torrent} on PubSub "torrents:{hash}"

TorexWeb.TorrentChannel (handle_info)
    → pushes "diffs" or "updated" events to connected WebSocket clients

TorexWeb.DashboardLive (handle_info)
    → updates assigns, LiveView re-renders
```

Both Channels and LiveView subscribe to the **same PubSub topics**, ensuring consistency.

## Module quick reference

| Module | Purpose |
|---|---|
| `TaniwhaWeb.Endpoint` | Phoenix endpoint configuration |
| `TaniwhaWeb.Router` | Route definitions (REST + LiveView + health) |
| `TaniwhaWeb.UserSocket` | WebSocket entry point, JWT verification |
| `TaniwhaWeb.TorrentChannel` | Channel for real-time torrent data (500 ms rate limit per socket) |
| `TaniwhaWeb.Plugs.AuthenticateToken` | REST API JWT plug |
| `TaniwhaWeb.Plugs.RateLimit` | ETS-backed sliding-window rate limit plug (auth endpoint) |
| `TaniwhaWeb.HealthController` | Unauthenticated health check (`GET /health`) |
| `TaniwhaWeb.API.AuthController` | JWT token exchange endpoint |
| `TaniwhaWeb.API.TorrentController` | REST torrent operations |
| `TaniwhaWeb.DashboardLive` | Main torrent list UI |
| `TaniwhaWeb.TorrentDetailLive` | Single torrent detail UI |
| `TaniwhaWeb.AddTorrentLive` | Add torrent form |
| `TaniwhaWeb.SettingsLive` | Settings view |
| `TaniwhaWeb.TorrentComponents` | Reusable UI function components |
| `Taniwha.RateLimiter` | ETS GenServer powering `Plugs.RateLimit` (lives in core, not web) |

## Channel protocol summary

**Topics:** `torrents:list`, `torrents:{hash}`

**Client → Server:** `start`, `stop`, `remove`, `set_file_priority`
— Rate limited to one command per 500 ms per socket. Excess commands receive `{:error, %{reason: "rate_limited"}}`.

**Server → Client:** `diffs` (list of changes), `updated` (single torrent)

## REST endpoints

- `POST /api/v1/auth/token` — exchange API key for JWT
- `POST /api/v1/torrents` — add torrent (magnet or file upload)
- `GET /api/v1/torrents` — snapshot all torrents
- `GET /api/v1/torrents/:hash` — snapshot one torrent

## Testing approach

- **Channels:** `Phoenix.ChannelTest` — join, push, assert replies and broadcasts.
- **Controllers:** `Phoenix.ConnTest` — HTTP request/response cycle.
- **LiveView:** `Phoenix.LiveViewTest` — mount, events, PubSub-driven updates.
- All tests mock `Taniwha.Commands` — no real rtorrent interaction in web tests.

## Accessibility (Phase 5+)

- WCAG 2.2 AA compliance target.
- Semantic HTML5, proper heading hierarchy, ARIA landmarks.
- axe-core in test pipeline (added when LiveView work begins).