## Why

Users who want to add multiple torrents at once must currently repeat the add-torrent flow for each item, which is tedious and error-prone. Supporting bulk add (multiple magnet links or multiple torrent files in a single operation) reduces friction for common workflows such as adding an entire season of a show or a batch download list.

## What Changes

- The "Add Torrent" modal gains a multi-magnet-link mode: the first text field remains, and a "+" button lets the user append additional magnet link fields; each extra field gets a paired "-" button to remove it independently (the first field cannot be removed).
- The torrent-file drop zone and file picker are updated to accept multiple files simultaneously.
- A single label and a single download folder apply to all torrents in the batch.
- The backend `Commands.add_torrent/2` API is extended (or a new `Commands.add_torrents/2` added) to accept a list of magnet URIs or file binaries and submit them in sequence (or via multicall).
- No mixed-mode: the modal tab determines whether the batch is magnets or files; switching tabs resets the inputs.

## Capabilities

### New Capabilities

- `bulk-add-torrents`: Add multiple torrent files or magnet links in a single modal interaction, sharing a common label and download folder.

### Modified Capabilities

- `add-torrent`: The existing single-add flow's UI and backend entry point are modified to support n ≥ 1 items, making the single-add a degenerate case of bulk-add.

## Impact

- **LiveView**: `TaniwhaWeb.Live.AddTorrentModal` (or equivalent component) — significant changes to form layout and event handling.
- **Commands**: `Taniwha.Commands` — new or extended function to submit a list of torrents.
- **RPC**: `Taniwha.RPC.Client` / `Taniwha.XMLRPC` — may need `system.multicall` support for efficient batch submission.
- **No new dependencies** expected; reuses existing file-upload and SCGI transport.
