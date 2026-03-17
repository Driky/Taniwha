# Taniwha — Implementation Roadmap

Each task has a corresponding prompt file in `prompts/` designed for Claude Code planning mode with a team of agents (architect, devil's advocate, UX/UI expert).

---

## Phase 1 — Scaffolding

| Task | Prompt | Description |
|---|---|---|
| 1.1 | `prompts/phase-1/1.1-project-creation.md` | Phoenix project creation + dependencies |
| 1.2 | `prompts/phase-1/1.2-ci-pipeline.md` | GitHub Actions CI (lint, test, build) |
| 1.3 | `prompts/phase-1/1.3-docker-cd.md` | Dockerfile + CD pipeline (GHCR + SSH deploy) |
| 1.4 | `prompts/phase-1/1.4-documentation.md` | CLAUDE.md files, architecture doc, README |

## Phase 2 — Transport + RPC

| Task | Prompt | Description |
|---|---|---|
| 2.1 | `prompts/phase-2/2.1-scgi-protocol.md` | SCGI protocol encode/decode |
| 2.2 | `prompts/phase-2/2.2-xmlrpc-codec.md` | XML-RPC codec |
| 2.3 | `prompts/phase-2/2.3-connection-behaviour.md` | Connection behaviour + Unix/TCP implementations |
| 2.4 | `prompts/phase-2/2.4-rpc-client.md` | RPC GenServer client + multicall |

## Phase 3 — Domain + State

| Task | Prompt | Description |
|---|---|---|
| 3.1 | `prompts/phase-3/3.1-domain-types.md` | Torrent struct + domain types |
| 3.2 | `prompts/phase-3/3.2-commands.md` | Commands module (public rtorrent API) |
| 3.3 | `prompts/phase-3/3.3-ets-store.md` | ETS store |
| 3.4 | `prompts/phase-3/3.4-poller-diff.md` | Poller + diff engine + PubSub broadcast |

## Phase 4 — WebSocket + REST API

| Task | Prompt | Description |
|---|---|---|
| 4.1 | `prompts/phase-4/4.1-jwt-auth.md` | JWT authentication (Guardian) |
| 4.2 | `prompts/phase-4/4.2-phoenix-channel.md` | Phoenix Channel (torrent channel) |
| 4.3 | `prompts/phase-4/4.3-rest-api.md` | REST API endpoints |
| 4.4 | `prompts/phase-4/4.4-protocol-docs.md` | Channel protocol documentation |

## Phase 5 — LiveView UI

| Task | Prompt | Description |
|---|---|---|
| 5.1 | `prompts/phase-5/5.1-layout-components.md` | Layout, navigation, torrent components |
| 5.2 | `prompts/phase-5/5.2-dashboard-live.md` | Dashboard LiveView |
| 5.3 | `prompts/phase-5/5.3-torrent-detail-live.md` | Torrent detail LiveView |
| 5.4 | `prompts/phase-5/5.4-add-settings-live.md` | Add torrent + settings LiveViews |

## Phase 6 — Polish + Release

| Task | Prompt | Description |
|---|---|---|
| 6.1 | `prompts/phase-6/6.1-error-handling.md` | Error handling, reconnection, resilience |
| 6.2 | `prompts/phase-6/6.2-integration-tests.md` | Integration tests + Docker dev environment |
| 6.3 | `prompts/phase-6/6.3-final-polish.md` | Rate limiting, health checks, release prep |
