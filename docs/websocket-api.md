# Taniwha WebSocket API

## Table of Contents

1. [Overview](#1-overview)
2. [Authentication](#2-authentication)
3. [Phoenix Wire Protocol](#3-phoenix-wire-protocol-for-non-phoenixjs-clients)
4. [Topics and Joining](#4-topics-and-joining)
5. [Torrent Object Reference](#5-torrent-object-reference)
6. [Server → Client Events](#6-server--client-events)
7. [Client → Server Commands](#7-client--server-commands)
8. [Applying Diffs — Pseudocode](#8-applying-diffs--pseudocode)
9. [Error Handling & Reconnection](#9-error-handling--reconnection)
10. [REST API Quick Reference](#10-rest-api-quick-reference)
11. [Annotated Example Session](#11-annotated-example-session)
12. [Client Library Examples](#12-client-library-examples)

---

## 1. Overview

Taniwha wraps an [rtorrent](https://github.com/rakshasa/rtorrent) instance behind a
modern WebSocket API. Connected clients receive real-time torrent status updates and
can issue lifecycle commands (start, stop, remove, set file priority) without polling.

**What this API enables:**

- Subscribe to a live diff stream for all torrents or a single torrent.
- Send commands and receive synchronous replies with success/error status.
- Build web, mobile, or desktop clients without depending on rtorrent's native protocol.

### Phoenix Channels primer

Taniwha's real-time API is built on [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html).
If you are not familiar with Phoenix:

- A **topic** is a named room (`"torrents:list"`, `"torrents:abc123…"`).
- **Joining** a topic sends you an initial snapshot of the current state, then
  subscribes you to incremental push events (diffs).
- **Pushing** is a command sent from client to server; the server replies
  synchronously with success or error.

```
Client                            Server
  │                                  │
  │  POST /api/v1/auth/token         │
  │ ────────────────────────────────►│
  │  {"token":"<jwt>"}               │
  │ ◄────────────────────────────────│
  │                                  │
  │  WS /socket/websocket?token=…    │
  │ ════════════════════════════════►│  (upgrade)
  │                                  │
  │  join "torrents:list"            │
  │ ────────────────────────────────►│
  │  {"torrents":[…]}  (snapshot)    │
  │ ◄────────────────────────────────│
  │                                  │
  │         {"diffs":[…]}            │
  │ ◄────────────────────────────────│  (pushed on change)
  │                                  │
  │  push "stop" {"hash":"…"}        │
  │ ────────────────────────────────►│
  │  {"status":"ok", "response":{}}  │
  │ ◄────────────────────────────────│
```

---

## 2. Authentication

All API access requires a JWT. The two-step flow is:

### Step 1 — Obtain a token

```
POST /api/v1/auth/token
Content-Type: application/json

{"api_key": "<your-api-key>"}
```

**Success (200):**
```json
{"token": "<jwt>"}
```

**Error responses:**

| Status | Body | Meaning |
|--------|------|---------|
| 401 | `{"error":"invalid_api_key"}` | Key does not match server config |
| 422 | `{"error":"api_key is required"}` | `api_key` field missing from body |

### Step 2 — Connect the WebSocket

```
wss://{host}/socket/websocket?token={jwt}
```

- The socket is mounted at `/socket`; Phoenix appends `/websocket` for the WebSocket
  transport (there is no `/v1` prefix on WebSocket paths).
- The query parameter name is `token` (not `Authorization`).
- If the token is missing or invalid, the WebSocket handshake is rejected with HTTP 403.

### Token lifetime and refresh

- Tokens expire after **1 hour**.
- There is no refresh endpoint in v1.
- Token validity is checked only at connection time. An already-connected socket is
  **not disconnected** when its token expires mid-session.
- **Refresh strategy:** re-POST `/api/v1/auth/token` with your API key to get a new
  token, then reconnect the WebSocket and re-join your topics. The join reply provides
  a fresh snapshot, so no state is lost.

---

## 3. Phoenix Wire Protocol (for non-phoenix.js clients)

If you are not using the official `phoenix` npm package, you must implement the wire
protocol yourself. Each Phoenix message is a 5-element JSON array:

```
[join_ref, ref, topic, event, payload]
```

| Element | Type | Description |
|---------|------|-------------|
| `join_ref` | string \| null | Identifies the channel join. Set when joining; null for heartbeats and some server pushes. |
| `ref` | string \| null | Identifies this individual message. Echo'd back in replies. null for server-pushed events. |
| `topic` | string | The channel topic (e.g., `"torrents:list"`). |
| `event` | string | Event name (e.g., `"phx_join"`, `"stop"`, `"diffs"`). |
| `payload` | object | Event-specific payload. |

**Built-in events:**

| Event | Direction | Meaning |
|-------|-----------|---------|
| `phx_join` | client → server | Join a topic |
| `phx_leave` | client → server | Leave a topic |
| `phx_reply` | server → client | Reply to a client message (echoes `ref`) |
| `phx_error` | server → client | Channel process crashed |
| `phx_close` | server → client | Channel closed normally |
| `heartbeat` | client → server | Keep-alive ping (topic `"phoenix"`) |

**Heartbeat (required):** send every 30 seconds or the server will close the connection.

```json
[null, "1", "phoenix", "heartbeat", {}]
```

The server replies:
```json
[null, "1", "phoenix", "phx_reply", {"status":"ok","response":{}}]
```

**Recommendation:** use the official [`phoenix` npm package](https://www.npmjs.com/package/phoenix)
when possible — it handles heartbeats, ref numbering, reconnection backoff, and reply
correlation automatically.

---

## 4. Topics and Joining

### 4.1 `torrents:list`

Streams the complete torrent list with incremental diffs.

**Join:**
```json
[join_ref, ref, "torrents:list", "phx_join", {}]
```

**Success reply:**
```json
{
  "status": "ok",
  "response": {
    "torrents": [<torrent_object>, …]
  }
}
```

The `torrents` array may be empty if no torrents are loaded. After a successful join,
the server pushes `diffs` events whenever the torrent list changes.

### 4.2 `torrents:{hash}`

Streams updates for a single torrent identified by its info-hash.

**Join:**
```json
[join_ref, ref, "torrents:abc123…", "phx_join", {}]
```

**Success reply:**
```json
{
  "status": "ok",
  "response": {
    "torrent": <torrent_object>
  }
}
```

**Rejected join (torrent not found):**
```json
{
  "status": "error",
  "response": {
    "reason": "torrent_not_found"
  }
}
```

After a successful join, the server pushes `updated` events whenever a tracked field
changes for this torrent.

> **v1 limitation — silent removal:** if the torrent is deleted while you hold this
> subscription, the `torrents:{hash}` channel sends **no notification**. Only
> `torrents:list` subscribers see the `removed` diff.
>
> **Recommended pattern:** subscribe to `torrents:list` in parallel; watch for
> `{"type":"removed","data":{"hash":"…"}}` diffs matching your hash of interest,
> then call leave on the `torrents:{hash}` channel.

---

## 5. Torrent Object Reference

The torrent object appears in join replies, `diffs` payloads, and `updated` events.
All field names are camelCase strings.

| Field | Type | Unit | Null? | Notes | Triggers diff? |
|-------|------|------|-------|-------|----------------|
| `hash` | string | — | no | Info-hash (hex). Stable identifier. | — |
| `name` | string | — | no | Torrent display name. | no (static) |
| `size` | integer | bytes | no | Total torrent size. 0 until initialized. | no (static) |
| `completedBytes` | integer | bytes | no | Bytes downloaded. | **yes** |
| `uploadRate` | integer | bytes/s | no | Current upload rate. | **yes** |
| `downloadRate` | integer | bytes/s | no | Current download rate. | **yes** |
| `ratio` | float | — | no | Upload/download ratio (e.g., 1.5 = 150%). | **yes** |
| `state` | string | — | no | `"started"` or `"stopped"`. | **yes** |
| `isActive` | boolean | — | no | rtorrent "active" flag (transferring data). | **yes** |
| `complete` | boolean | — | no | All bytes downloaded. | **yes** |
| `isHashChecking` | boolean | — | no | Currently verifying data integrity. | **yes** |
| `peersConnected` | integer | — | no | Number of connected peers. | **yes** |
| `startedAt` | string \| null | ISO 8601 UTC | yes | Time rtorrent first started the torrent. null if never started. | no |
| `finishedAt` | string \| null | ISO 8601 UTC | yes | Time download completed. null if not finished. | no |
| `basePath` | string \| null | — | yes | Filesystem path to download location. null until rtorrent assigns it. | no (static) |
| `progress` | float | — | no | `completedBytes / size`, range 0.0–1.0. 0.0 when size is 0. Server-derived; use as-is. | — |
| `status` | string | — | no | Human-readable semantic status (see below). Server-derived; use as-is. | — |

### Status derivation

The `status` field is computed server-side from the raw flags. Evaluation order matters:

| Condition | `status` value |
|-----------|---------------|
| `isHashChecking: true` | `"checking"` |
| `state: "started"`, `isActive: true`, `complete: false` | `"downloading"` |
| `state: "started"`, `isActive: true`, `complete: true` | `"seeding"` |
| `state: "started"`, `isActive: false` | `"paused"` |
| `state: "stopped"` | `"stopped"` |
| (none of the above) | `"unknown"` |

---

## 6. Server → Client Events

### 6.1 `diffs` (on `torrents:list`)

Pushed to all `torrents:list` subscribers when the torrent list changes. Empty diff
cycles are suppressed — nothing is sent if no tracked field changed.

**Payload:**
```json
{
  "diffs": [
    {"type": "added",   "data": <torrent_object>},
    {"type": "updated", "data": <torrent_object>},
    {"type": "removed", "data": {"hash": "<hash>"}}
  ]
}
```

| `type` | `data` content |
|--------|---------------|
| `"added"` | Full torrent object (new torrent appeared). |
| `"updated"` | Full torrent object (one or more diff fields changed). |
| `"removed"` | `{"hash": "<hash>"}` only — not a full torrent object. |

A single `diffs` message may contain a mix of `added`, `updated`, and `removed` entries.

### 6.2 `updated` (on `torrents:{hash}`)

Pushed to `torrents:{hash}` subscribers when a tracked field changes for that torrent.
Only fires when at least one diff field has changed since the previous poll.

**Payload:**
```json
{
  "torrent": <torrent_object>
}
```

The full torrent object is sent every time (not a sparse patch). Merge by replacing
your stored state entirely.

---

## 7. Client → Server Commands

Commands are sent as pushes on any channel the client has joined. The server replies
synchronously via `phx_reply`.

| Event | Channel | Required payload fields | Success response | Error response |
|-------|---------|------------------------|-----------------|----------------|
| `start` | either | `hash` (string) | `{}` | `{"reason":"<string>"}` |
| `stop` | either | `hash` (string) | `{}` | `{"reason":"<string>"}` |
| `remove` | either | `hash` (string) | `{}` | `{"reason":"<string>"}` |
| `set_file_priority` | either | `hash` (string), `index` (integer), `priority` (0\|1\|2) | `{}` | `{"reason":"<string>"}` |

**Priority values for `set_file_priority`:**

| Value | Meaning |
|-------|---------|
| `0` | Skip (do not download) |
| `1` | Normal priority |
| `2` | High priority |

File `index` is zero-based and corresponds to the file's position in the torrent's
`info.files` array (as defined in the `.torrent` metadata).

> **v1 limitation — no file listing:** the API does not expose a file list or file
> indices. To use `set_file_priority`, clients must determine file indices from the
> `.torrent` file metadata. A `GET /api/v1/torrents/:hash/files` endpoint is planned
> for a future release.

**Note on error reasons:** the `reason` string is Elixir's `inspect/1` output of
whatever the underlying command returned. These are diagnostic strings for display
and logging — treat them as **opaque** and do not attempt to parse them programmatically.

---

## 8. Applying Diffs — Pseudocode

```
# State model
torrents = {}          # hash → torrent_object

# --- Initialise from join reply ---
on join_reply(response):
    for torrent in response["torrents"]:
        torrents[torrent["hash"]] = torrent

# --- Apply diffs from "diffs" event ---
on diffs_event(payload):
    for diff in payload["diffs"]:
        if diff["type"] == "added":
            torrents[diff["data"]["hash"]] = diff["data"]

        elif diff["type"] == "updated":
            # "updated" currently sends the full torrent object; replace, not merge
            torrents[diff["data"]["hash"]] = diff["data"]

        elif diff["type"] == "removed":
            del torrents[diff["data"]["hash"]]

# --- Apply update from "updated" event (torrents:{hash} channel) ---
on updated_event(payload):
    torrent = payload["torrent"]
    # Full object every time; replace stored state
    torrents[torrent["hash"]] = torrent
```

> **Merge semantics:** `updated` diffs send the full torrent object, not a sparse
> patch. Replace your stored object entirely — do not attempt a field-level merge.

---

## 9. Error Handling & Reconnection

### Error scenarios

| Scenario | What happens |
|----------|-------------|
| Bad or expired token at connect time | WebSocket handshake rejected with HTTP 403 |
| Token missing (no `token` param) | WebSocket handshake rejected with HTTP 403 |
| Join with unknown hash | Server replies with `{"reason":"torrent_not_found"}` |
| Command fails (RPC error) | Server replies with `{"reason":"<diagnostic string>"}` |
| Server restart or channel crash | WebSocket closes; client should reconnect |
| Torrent removed while subscribed to `torrents:{hash}` | No notification on that channel (v1 limitation; see §4.2) |

### Reconnection pseudocode

```
BACKOFF_MS = [1000, 2000, 4000, 8000, 16000, 30000]

function reconnect_with_backoff():
    attempt = 0
    while true:
        wait(BACKOFF_MS[min(attempt, len(BACKOFF_MS) - 1)])
        try:
            # Re-authenticate (token may have expired during outage)
            response = POST /api/v1/auth/token {"api_key": stored_api_key}
            token = response["token"]

            # Reconnect WebSocket
            connect wss://{host}/socket/websocket?token={token}

            # Re-join all previously joined topics
            for topic in previously_joined_topics:
                join(topic)
                # Join reply delivers a fresh snapshot — no state is lost

            attempt = 0   # reset backoff on success
            return

        except error:
            attempt += 1
```

---

## 10. REST API Quick Reference

All authenticated endpoints require the `Authorization: Bearer <jwt>` header (added
by `TaniwhaWeb.Plugs.AuthenticateToken`).

| Method | Path | Auth | Description | Success | Error |
|--------|------|------|-------------|---------|-------|
| `POST` | `/api/v1/auth/token` | no | Exchange API key for JWT | 200 `{"token":"…"}` | 401 / 422 (see §2) |
| `GET` | `/api/v1/torrents` | yes | Snapshot all torrents | 200 `{"torrents":[…]}` | 401 |
| `GET` | `/api/v1/torrents/:hash` | yes | Snapshot one torrent | 200 `{"torrent":{…}}` | 401 / 404 |
| `POST` | `/api/v1/torrents` | yes | Add torrent (magnet or file upload) | 200 `{"status":"…"}` | 401 / 422 |

See §2 for authentication details. The WebSocket API (§3–§9) provides the same
torrent data with live updates and is the preferred interface for interactive clients.

---

## 11. Annotated Example Session

This walkthrough traces a complete client session at the wire level using Phoenix's
5-element array format. `→` is client-to-server, `←` is server-to-client.

### Step 1 — Obtain a JWT (HTTP)

```
→ POST /api/v1/auth/token
   Content-Type: application/json
   {"api_key": "secret"}

← 200 OK
   {"token": "eyJ..."}
```

### Step 2 — Open the WebSocket

```
→ GET /socket/websocket?token=eyJ...
   Upgrade: websocket
   ...

← 101 Switching Protocols
```

The handshake is a standard WebSocket upgrade. Phoenix verifies the token before
accepting the connection. HTTP 403 means the token was rejected.

### Step 3 — Join `torrents:list`

```
→ ["1", "1", "torrents:list", "phx_join", {}]
     ^join_ref  ^ref

← [null, "1", "torrents:list", "phx_reply",
   {
     "status": "ok",
     "response": {
       "torrents": [
         {
           "hash": "aabbcc…",
           "name": "Ubuntu 24.04 LTS",
           "size": 2097152000,
           "completedBytes": 1048576000,
           "uploadRate": 0,
           "downloadRate": 524288,
           "ratio": 0.0,
           "state": "started",
           "isActive": true,
           "complete": false,
           "isHashChecking": false,
           "peersConnected": 12,
           "startedAt": "2025-03-01T10:00:00Z",
           "finishedAt": null,
           "basePath": "/downloads/Ubuntu 24.04 LTS",
           "progress": 0.5,
           "status": "downloading"
         },
         {
           "hash": "ddeeff…",
           "name": "Debian 12.5",
           "size": 698351616,
           "completedBytes": 698351616,
           "uploadRate": 65536,
           "downloadRate": 0,
           "ratio": 1.2,
           "state": "started",
           "isActive": true,
           "complete": true,
           "isHashChecking": false,
           "peersConnected": 3,
           "startedAt": "2025-02-20T08:00:00Z",
           "finishedAt": "2025-02-20T09:15:00Z",
           "basePath": "/downloads/Debian 12.5",
           "progress": 1.0,
           "status": "seeding"
         }
       ]
     }
   }]
```

The server echoes the `ref` (`"1"`) so the client can match this reply to the join
request. `join_ref` is null in server-push messages.

### Step 4 — Receive a `diffs` event (progress update)

The server polls rtorrent periodically. When `completedBytes` or another tracked
field changes, it pushes a diff:

```
← [null, null, "torrents:list", "diffs",
   {
     "diffs": [
       {
         "type": "updated",
         "data": {
           "hash": "aabbcc…",
           "name": "Ubuntu 24.04 LTS",
           "size": 2097152000,
           "completedBytes": 1258291200,
           "uploadRate": 0,
           "downloadRate": 524288,
           "ratio": 0.0,
           "state": "started",
           "isActive": true,
           "complete": false,
           "isHashChecking": false,
           "peersConnected": 11,
           "startedAt": "2025-03-01T10:00:00Z",
           "finishedAt": null,
           "basePath": "/downloads/Ubuntu 24.04 LTS",
           "progress": 0.6,
           "status": "downloading"
         }
       }
     ]
   }]
```

Both `join_ref` and `ref` are null for unsolicited server pushes.

### Step 5 — Send a `stop` command

```
→ ["1", "2", "torrents:list", "stop", {"hash": "aabbcc…"}]
       ^ref

← [null, "2", "torrents:list", "phx_reply",
   {"status": "ok", "response": {}}]
```

The server echoes `ref` `"2"`. An empty `response` (`{}`) means success.

### Step 6 — Receive next `diffs` (state changed to "stopped")

```
← [null, null, "torrents:list", "diffs",
   {
     "diffs": [
       {
         "type": "updated",
         "data": {
           "hash": "aabbcc…",
           ...
           "state": "stopped",
           "isActive": false,
           "downloadRate": 0,
           "status": "stopped"
         }
       }
     ]
   }]
```

### Step 7 — Join `torrents:{hash}` for single-torrent detail

```
→ ["2", "3", "torrents:aabbcc…", "phx_join", {}]

← [null, "3", "torrents:aabbcc…", "phx_reply",
   {
     "status": "ok",
     "response": {
       "torrent": {
         "hash": "aabbcc…",
         ...
         "status": "stopped"
       }
     }
   }]
```

### Step 8 — Send `set_file_priority`

> **Note:** file index `0` refers to the first file in the torrent's `info.files`
> list. Determine indices from `.torrent` metadata — the API does not expose a file
> listing in v1.

```
→ ["2", "4", "torrents:aabbcc…", "set_file_priority",
   {"hash": "aabbcc…", "index": 0, "priority": 2}]

← [null, "4", "torrents:aabbcc…", "phx_reply",
   {"status": "ok", "response": {}}]
```

### Step 9 — Disconnect and reconnect (token refresh)

The server closes the WebSocket (e.g., on restart):

```
← WebSocket close frame
```

Client reconnects:

```
→ POST /api/v1/auth/token {"api_key": "secret"}
← 200 {"token": "eyJ...new..."}

→ GET /socket/websocket?token=eyJ...new...
← 101 Switching Protocols

→ ["1", "1", "torrents:list", "phx_join", {}]
← [null, "1", "torrents:list", "phx_reply", {"status":"ok","response":{"torrents":[…]}}]
```

The join reply delivers a fresh snapshot. No state is lost.

---

## 12. Client Library Examples

### 12.1 JavaScript — phoenix.js

The `phoenix` npm package handles heartbeats, reconnection, ref numbering, and reply
correlation automatically.

```javascript
import { Socket } from "phoenix"

// --- 1. Obtain token ---
async function getToken(host, apiKey) {
  const response = await fetch(`https://${host}/api/v1/auth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: apiKey }),
  })
  if (!response.ok) throw new Error(`Auth failed: ${response.status}`)
  const { token } = await response.json()
  return token
}

// --- 2. Connect and join ---
async function connect(host, apiKey) {
  const token = await getToken(host, apiKey)

  const socket = new Socket(`wss://${host}/socket`, {
    params: { token },
  })

  socket.onClose(() => {
    console.log("Socket closed — reconnecting with fresh token…")
    // phoenix.js reconnects automatically, but the token may have expired.
    // Update params before the next reconnect attempt:
    getToken(host, apiKey).then(newToken => {
      socket.params = () => ({ token: newToken })
    })
  })

  socket.connect()

  // --- 3. Join torrents:list ---
  const listChannel = socket.channel("torrents:list")

  listChannel.on("diffs", ({ diffs }) => {
    for (const diff of diffs) {
      if (diff.type === "added")   addTorrent(diff.data)
      if (diff.type === "updated") updateTorrent(diff.data)
      if (diff.type === "removed") removeTorrent(diff.data.hash)
    }
  })

  listChannel
    .join()
    .receive("ok", ({ torrents }) => {
      console.log("Joined torrents:list, snapshot:", torrents)
      for (const t of torrents) addTorrent(t)
    })
    .receive("error", ({ reason }) => {
      console.error("Join failed:", reason)
    })

  // --- 4. Send a command ---
  function stopTorrent(hash) {
    listChannel
      .push("stop", { hash })
      .receive("ok", () => console.log("Stopped", hash))
      .receive("error", ({ reason }) => console.error("Stop failed:", reason))
  }

  return { socket, listChannel, stopTorrent }
}
```

### 12.2 Python — websockets

This example manually implements the Phoenix wire protocol using the `websockets`
library (asyncio). Install with `pip install websockets`.

```python
import asyncio
import json
import urllib.parse
import httpx
import websockets

HOST = "example.com"
API_KEY = "secret"
REF = 0


def next_ref():
    global REF
    REF += 1
    return str(REF)


async def get_token():
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"https://{HOST}/api/v1/auth/token",
            json={"api_key": API_KEY},
        )
        resp.raise_for_status()
        return resp.json()["token"]


def make_message(join_ref, ref, topic, event, payload):
    return json.dumps([join_ref, ref, topic, event, payload])


async def main():
    token = await get_token()
    uri = f"wss://{HOST}/socket/websocket?" + urllib.parse.urlencode({"token": token})

    async with websockets.connect(uri) as ws:
        # Join torrents:list
        join_ref = next_ref()
        ref = next_ref()
        await ws.send(make_message(join_ref, ref, "torrents:list", "phx_join", {}))

        # Wait for join reply
        while True:
            msg = json.loads(await ws.recv())
            # [join_ref_echo, ref_echo, topic, event, payload]
            _, msg_ref, _, event, payload = msg
            if event == "phx_reply" and msg_ref == ref:
                if payload["status"] == "ok":
                    torrents = payload["response"]["torrents"]
                    print(f"Joined; snapshot has {len(torrents)} torrent(s)")
                else:
                    raise RuntimeError(f"Join error: {payload['response']}")
                break

        # Send a stop command
        cmd_ref = next_ref()
        hash_to_stop = torrents[0]["hash"] if torrents else None
        if hash_to_stop:
            await ws.send(
                make_message(join_ref, cmd_ref, "torrents:list", "stop",
                             {"hash": hash_to_stop})
            )

        # Heartbeat task
        async def heartbeat():
            while True:
                await asyncio.sleep(30)
                hb_ref = next_ref()
                await ws.send(make_message(None, hb_ref, "phoenix", "heartbeat", {}))

        asyncio.create_task(heartbeat())

        # Main event loop
        async for raw in ws:
            msg = json.loads(raw)
            _, msg_ref, topic, event, payload = msg

            if event == "phx_reply" and msg_ref == cmd_ref:
                if payload["status"] == "ok":
                    print(f"Stop succeeded for {hash_to_stop}")
                else:
                    print(f"Stop failed: {payload['response']['reason']}")

            elif event == "diffs":
                for diff in payload["diffs"]:
                    print(f"Diff: type={diff['type']} hash={diff['data'].get('hash')}")

            elif event == "updated":
                t = payload["torrent"]
                print(f"Updated: {t['hash']} status={t['status']}")

            elif event in ("phx_reply",):
                pass  # heartbeat reply, etc.


asyncio.run(main())
```

### 12.3 Swift — URLSessionWebSocketTask (conceptual)

For iOS/macOS clients using `URLSessionWebSocketTask` from Foundation:

```swift
import Foundation

// Codable types for Phoenix wire protocol
struct PhxMessage: Codable {
    let joinRef: String?
    let ref: String?
    let topic: String
    let event: String
    let payload: [String: AnyCodable]  // use a type-erased wrapper

    // Encode/decode as 5-element array
    // Phoenix sends: [join_ref, ref, topic, event, payload]
}

class TaniwhaClient {
    private var socket: URLSessionWebSocketTask?
    private var refCounter = 0
    private var joinRef: String?
    private var heartbeatTimer: Timer?

    // Increment and return a unique ref string
    private func nextRef() -> String {
        refCounter += 1
        return String(refCounter)
    }

    func connect(host: String, token: String) {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = "/socket/websocket"
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else { return }
        let session = URLSession(configuration: .default)
        socket = session.webSocketTask(with: url)
        socket?.resume()

        receive()
        startHeartbeat()
        joinChannel(topic: "torrents:list")
    }

    private func joinChannel(topic: String) {
        joinRef = nextRef()
        let ref = nextRef()
        // Send: [joinRef, ref, topic, "phx_join", {}]
        let msg = [joinRef!, ref, topic, "phx_join", "{}"] as [Any]
        send(message: msg)
    }

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let ref = self.nextRef()
            // Send: [null, ref, "phoenix", "heartbeat", {}]
            let msg = [NSNull(), ref, "phoenix", "heartbeat", "{}"] as [Any]
            self.send(message: msg)
        }
    }

    private func send(message: [Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        socket?.send(.data(data)) { _ in }
    }

    private func receive() {
        socket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                // Parse the 5-element array and dispatch on event name
                self?.handle(message: message)
                self?.receive()  // schedule next receive
            case .failure:
                self?.scheduleReconnect()
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        // Deserialize the 5-element array:
        // [join_ref, ref, topic, event, payload]
        // Dispatch on event ("diffs", "updated", "phx_reply", etc.)
    }

    private func scheduleReconnect() {
        // Re-authenticate and reconnect with exponential backoff (see §9)
    }

    func sendCommand(_ event: String, payload: [String: Any]) {
        let ref = nextRef()
        let msg = [joinRef!, ref, "torrents:list", event, payload] as [Any]
        send(message: msg)
        // Correlate reply by matching msg_ref == ref in handle(message:)
    }
}
```

Community Phoenix client libraries for Swift exist (e.g., `SwiftPhoenixClient`) but
require your own evaluation before adopting. The approach above has no third-party
dependencies.

---

## Known v1 Protocol Gaps

| Gap | v1 handling |
|-----|-------------|
| `torrents:{hash}` not notified on torrent removal | Documented as limitation; subscribe to `torrents:list` in parallel and watch for `removed` diffs (§4.2). |
| No file listing endpoint (needed for `set_file_priority` indices) | Documented as limitation; derive indices from `.torrent` metadata (§7). `GET /api/v1/torrents/:hash/files` is planned. |
| No JWT refresh endpoint | Documented; reconnect + re-authenticate strategy provided (§2, §9). |
