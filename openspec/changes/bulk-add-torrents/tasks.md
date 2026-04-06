## 1. Commands Layer

- [x] 1.1 Add `load_urls/2` to `Taniwha.Commands`: accepts `[String.t()]` and `keyword()`, calls `load_url/2` for each, returns `{:ok, count}` or `{:error, [{url, reason}]}`
- [x] 1.2 Add `load_raws/2` to `Taniwha.Commands`: accepts `[binary()]` and `keyword()`, calls `load_raw/2` for each, returns `{:ok, count}` or `{:error, [{index, reason}]}`
- [x] 1.3 Add `@spec` and `@doc` for both new functions
- [x] 1.4 Write unit tests for `load_urls/2`: all-success, partial-failure, all-failure cases
- [x] 1.5 Write unit tests for `load_raws/2`: all-success, partial-failure, all-failure cases

## 2. File Upload Configuration

- [x] 2.1 Change `allow_upload(:torrent_file, max_entries: 1, ...)` to `max_entries: 20` in `DashboardLive.mount/3`
- [x] 2.2 Update `DashboardLive.handle_event("submit_file", ...)` to call `Commands.load_raws/2` with all consumed entries
- [x] 2.3 Update file-tab error display in `AddTorrentComponent` to show per-file errors from a batch result
- [x] 2.4 Write tests for multi-file upload: all succeed, partial failure, max-entries enforcement

## 3. Multi-URL UI in AddTorrentComponent

- [x] 3.1 Replace `:url :: String.t()` assign with `:urls :: [String.t()]` (initialised to `[""]`)
- [x] 3.2 Add `handle_event("add_url_field", ...)`: appends `""` to `:urls` (no-op if already 20 fields)
- [x] 3.3 Add `handle_event("remove_url_field", %{"index" => i}, ...)`: removes field at index `i` from `:urls` (no-op if `i == 0`)
- [x] 3.4 Add `handle_event("update_url", %{"index" => i, "url" => v}, ...)`: replaces `:urls` at index `i` with `v`
- [x] 3.5 Update `handle_event("switch_tab", ...)` to reset `:urls` to `[""]` when switching away from the URL tab
- [x] 3.6 Update `handle_event("submit_url", ...)` to collect all `:urls`, filter blanks, call `Commands.load_urls/2`, handle `{:ok, count}` and `{:error, failures}`
- [x] 3.7 On partial failure: remove successfully submitted URLs from `:urls`, display structured error list
- [x] 3.8 Write unit tests for all new/updated `handle_event` callbacks

## 4. Multi-URL UI Rendering

- [x] 4.1 Replace the single `<input>` for URL with a `for` loop over `@urls`, each with `phx-value-index`
- [x] 4.2 Render a "+" button for every field; disable "+" when `length(@urls) >= 20`
- [x] 4.3 Render a "−" button for every field except index 0; wire to `remove_url_field` event
- [x] 4.4 Use unique `id` attributes per field (`add-torrent-url-input-0`, `-1`, …) and paired `<label>` (or `aria-label`)
- [x] 4.5 Add a JS hook (or `phx-hook`) to move focus to the new field when "+" is clicked
- [x] 4.6 Replace single-error banner with a structured error list when `:errors` is a list of `{item, reason}` tuples
- [x] 4.7 Write LiveView component tests for: initial render, add field, remove field, max-fields disable, error list render

## 5. Accessibility & Polish

- [x] 5.1 Ensure each URL field has `aria-label="Magnet link N"` (or equivalent) for screen readers
- [x] 5.2 Ensure "−" buttons have `aria-label="Remove link N"` and "+" buttons have `aria-label="Add another link"`
- [x] 5.3 Verify tab order is sequential through all URL fields and action buttons
- [x] 5.4 Update the "Add" footer button `aria-label` to reflect batch context when N > 1 (e.g., "Add 3 torrents")
- [x] 5.5 Verify multi-file drop zone retains existing `aria-label` and `role` attributes

## 6. Regression & Integration

- [x] 6.1 Run the full test suite (`mix precommit`) and fix any regressions
- [ ] 6.2 Manual smoke test: single magnet link (existing behaviour unchanged)
- [ ] 6.3 Manual smoke test: 3 magnet links all succeed
- [ ] 6.4 Manual smoke test: 3 magnet links, one invalid — confirm partial failure display
- [ ] 6.5 Manual smoke test: multi-file drop and submit
