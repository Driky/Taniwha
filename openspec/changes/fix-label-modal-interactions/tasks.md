## 1. DashboardLive — capture hashes and pass mode

- [x] 1.1 Add `label_target_hashes: []` to initial assigns in `DashboardLive.mount/3`
- [x] 1.2 Update `context_menu_action` handler for `set_label_prompt` to pattern-match `hashes` and assign them to `label_target_hashes`; set `show_label_manager: true` and `label_manager_mode: :set`
- [x] 1.3 Update `show_label_manager` handler (sidebar path) to set `label_manager_mode: :manage` (hashes unchanged/empty)
- [x] 1.4 Add handler for `{:set_label_for_hashes, label, hashes}` message: call `Commands.set_label/2` per hash, reset `label_target_hashes: []`, set `show_label_manager: false`
- [x] 1.5 Update `hide_label_manager` path to also reset `label_target_hashes: []`

## 2. DashboardLive template — pass mode and hashes to component

- [x] 2.1 Pass `mode={@label_manager_mode}` and `target_hashes={@label_target_hashes}` to `LabelManagerComponent` in `dashboard_live.html.heex`

## 3. LabelManagerComponent — set mode rendering

- [x] 3.1 Add `select_label` event handler: call `send(self(), {:set_label_for_hashes, label, socket.assigns.target_hashes})` then `send(self(), {:hide_label_manager})`
- [x] 3.2 In `render/1`, conditionally render each label row as a `<button>` with `phx-click="select_label"` and `phx-value-label={name}` when `@mode == :set`; keep the existing `<div>` row (with edit/delete buttons) for `:manage` mode
- [x] 3.3 Apply `cursor-pointer` and a hover highlight class to the set-mode label row button

## 4. Sidebar cursor fix

- [x] 4.1 Add `cursor-pointer` to the "Manage labels" `<button>` class in `layout_components.ex`

## 5. Tests

- [x] 5.1 Write `LabelManagerComponent` test: in `:set` mode, clicking a label row sends `{:set_label_for_hashes, label, hashes}` to parent and hides the modal
- [x] 5.2 Write `LabelManagerComponent` test: in `:manage` mode, label rows do NOT have `phx-click="select_label"` and edit/delete buttons are present
- [x] 5.3 Write `DashboardLive` LiveView test: `set_label_prompt` context menu action with hashes opens modal in `:set` mode with correct `target_hashes`
- [x] 5.4 Write `DashboardLive` LiveView test: receiving `{:set_label_for_hashes, label, hashes}` calls `Commands.set_label/2` per hash and hides the modal
- [x] 5.5 Write `DashboardLive` LiveView test: dismissing the modal (close/Escape) resets `label_target_hashes` to `[]`
