## Context

Taniwha's "Add Torrent" modal (`TaniwhaWeb.AddTorrentComponent`) currently accepts exactly one magnet/URL or one `.torrent` file per submission. The LiveComponent holds a single `:url` string and `DashboardLive` configures `allow_upload(:torrent_file, max_entries: 1)`. The backend provides `Commands.load_url/2` and `Commands.load_raw/2`, each submitting a single item.

Users routinely need to add batches of torrents (e.g., a full season, a curated list) and must currently repeat the flow N times. This design extends both the UI and the Commands layer to support N ≥ 1 items in a single operation, while keeping the single-item path a degenerate case of the new path.

## Goals / Non-Goals

**Goals:**
- Support 1–N magnet links via a dynamic field list (add/remove individual fields).
- Support 1–N `.torrent` file uploads via the existing drop-zone (multi-select or multi-drop).
- Apply a single shared label and download directory to all items in the batch.
- Provide per-item error feedback when some items in a batch fail.
- Maintain WCAG 2.2 AA accessibility throughout the new UI.

**Non-Goals:**
- Mixed-mode batches (magnet links and files simultaneously).
- Per-item label or directory overrides.
- Retry UI — the user can re-open the modal or dismiss and fix the failing link.
- Multicall optimisation (`system.multicall`) — deferred to a future change.

## Decisions

### 1. URL state: list of strings instead of single string

**Decision:** Replace `:url :: String.t()` in `AddTorrentComponent` with `:urls :: [String.t()]` (always at least one element). Each entry maps to a rendered text field.

**Rationale:** A list maps directly to the rendered list of inputs. Adding/removing a field is an `Enum.delete_at/2` or list append. Validation iterates the list.

**Alternatives considered:**
- Map keyed by integer index — adds index-management complexity for no benefit.
- Keep single `:url` and add `:extra_urls` — two separate assigns is messy; merging before submission is error-prone.

### 2. Dynamic field identity: positional index

**Decision:** Fields are identified by their 0-based index in the `:urls` list. Events carry `phx-value-index`. The first field (index 0) can never be removed; all others show a "−" button.

**Rationale:** A stable list with no gaps means the index is stable for the lifetime of the field. There is no need for UUID-per-row; the list is ephemeral in-memory state.

**Risk:** If two rapid remove-clicks arrive in quick succession, the second may delete the wrong row. Mitigation: the "-" button is disabled during `:loading` and the state is server-authoritative.

### 3. File upload max_entries: 20

**Decision:** Change `allow_upload(:torrent_file, max_entries: 1, ...)` to `max_entries: 20` in `DashboardLive`.

**Rationale:** The LiveView upload API handles multi-file selection and multi-drop natively once `max_entries > 1`. No component changes are needed for the drop-zone itself; only the entry list display needs to support multiple rows. 20 is a reasonable upper bound for a single batch — large enough to cover most use cases, small enough to avoid DoS risk.

**Alternatives considered:**
- Unlimited entries — complicates the UI list and poses a resource risk.
- 5 entries — too restrictive for season-level batches.

### 4. Batch submission: sequential calls in the Commands layer

**Decision:** Add `Commands.load_urls/2` and `Commands.load_raws/2` that iterate their input lists and call the underlying single-item function for each, collecting `{:ok | {:error, reason}, item}` tuples. Return `{:ok, count}` if all succeed, `{:error, failures}` if any fail.

```elixir
@spec load_urls([String.t()], keyword()) :: {:ok, non_neg_integer()} | {:error, [{String.t(), term()}]}
def load_urls(urls, opts \\ []) do
  results = Enum.map(urls, fn url -> {url, load_url(url, opts)} end)
  failures = for {url, {:error, reason}} <- results, do: {url, reason}
  if failures == [], do: {:ok, length(urls)}, else: {:error, failures}
end
```

**Rationale:** Sequential is simple, correct, and avoids concurrency complexity for v1. An rtorrent instance processes `load.start` calls serially anyway. The per-item result map enables partial failure reporting.

**Alternatives considered:**
- `Task.async_stream` with concurrency — adds timeout handling, process supervision; unnecessary since rtorrent is effectively single-threaded on the load path.
- `system.multicall` — optimal round-trip count but requires new RPC plumbing; deferred.

### 5. Partial failure UX: report and stay open

**Decision:** If any items in a batch fail, the modal stays open. A structured error list replaces the current single-error banner: each failure shows the item identifier (URL prefix or filename) and the error reason. Successfully added items are removed from the form so the user can retry only the failed ones.

**Rationale:** Silently ignoring failures is dangerous — the user thinks they added everything. Closing the modal on partial success leaves the user without context. Keeping the modal open with a clear failure list is the safest UX.

### 6. Tab switch resets all inputs

**Decision:** Switching between the "Magnet / URL" and "File upload" tabs resets `:urls` to `[""]` and cancels all pending uploads, respectively. This matches the existing single-URL reset behaviour and prevents mixed-mode confusion.

## Risks / Trade-offs

- **Large URL lists degrade performance** → The sequential submission loop blocks the LiveView process. Mitigation: cap the magnet list at 20 fields in the UI (same as file limit).
- **LiveView upload API changes with max_entries** → Existing `cancel_upload` and `consume_uploaded_entries` code is entry-agnostic and should continue working. Verify in tests.
- **Accessibility with dynamic fields** → Each new URL input must have a unique `id` and associated `<label>`. Use index-based IDs (`add-torrent-url-input-0`, `-1`, …). Focus should move to the newly created field when "+" is clicked (via JS hook or `phx-hook`).

## Migration Plan

1. Update `DashboardLive.mount/3` to set `max_entries: 20`.
2. Extend `AddTorrentComponent` assigns (`:url` → `:urls`), update all `handle_event` callbacks, update `render/1`.
3. Add `Commands.load_urls/2` and `Commands.load_raws/2`; update `DashboardLive.handle_event("submit_file", ...)` and `AddTorrentComponent.handle_event("submit_url", ...)` to call the new functions.
4. Update error handling to display the structured failure list.
5. Update existing unit and integration tests; add tests for bulk paths.

No data migrations or infrastructure changes required. The change is fully backwards-compatible: a user who adds a single item follows the same code path as before.

## Open Questions

- **Focus management on "+ Add link"**: Should focus jump to the new field automatically? Preferred UX, but needs a small JS hook. Confirm before implementation.
- **Duplicate URL detection**: Should the submit handler warn if the same magnet link is entered twice? Not in scope for this design but easy to add.
