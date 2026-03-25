defmodule TaniwhaWeb.TorrentComponents.TableComponents do
  @moduledoc """
  Torrent table components: action bar, table header, torrent row, and the
  full table with the `.ContextMenu` ColocatedHook for right-click actions.
  """

  use TaniwhaWeb, :html

  import TaniwhaWeb.FormatHelpers, only: [format_bytes: 1, format_ratio: 1]

  import TaniwhaWeb.TorrentComponents.StatusComponents,
    only: [progress_bar: 1, speed_display: 1, status_badge: 1]

  alias Phoenix.LiveView.ColocatedHook
  alias Taniwha.Torrent

  # ---------------------------------------------------------------------------
  # action_bar/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the 32px bulk-action toolbar shown above the torrent table.

  Displays Start/Pause/Stop/Remove buttons and a torrent count. The deselect
  button only appears when one or more rows are selected.

  ## Attributes

  - `:visible_count` (required) — number of currently visible torrents
  - `:selected_count` — number of selected torrents, default 0
  - `:total_count` — total torrent count (may differ from visible), default 0

  ## Examples

      <.action_bar
        visible_count={length(visible)}
        selected_count={MapSet.size(@selected_hashes)}
        total_count={@total_count}
      />
  """
  attr :visible_count, :integer, required: true
  attr :selected_count, :integer, default: 0
  attr :total_count, :integer, default: 0

  def action_bar(assigns) do
    ~H"""
    <div
      class="flex items-center gap-1 px-3 border-b shrink-0"
      style="height: var(--taniwha-actionbar-h); background: var(--taniwha-actionbar-bg); border-color: var(--taniwha-actionbar-border)"
    >
      <button
        type="button"
        phx-click="bulk_start"
        disabled={@selected_count == 0}
        aria-label="Start selected torrents"
        class={[
          "inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded",
          @selected_count > 0 && "hover:bg-[#f3f4f6] cursor-pointer",
          @selected_count == 0 && "opacity-40 cursor-not-allowed"
        ]}
        style="color: var(--taniwha-col-header)"
      >
        <.icon name="hero-play-micro" class="size-3" /> Start
      </button>

      <button
        type="button"
        phx-click="bulk_stop"
        disabled={@selected_count == 0}
        aria-label="Stop selected torrents"
        class={[
          "inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded",
          @selected_count > 0 && "hover:bg-[#f3f4f6] cursor-pointer",
          @selected_count == 0 && "opacity-40 cursor-not-allowed"
        ]}
        style="color: var(--taniwha-col-header)"
      >
        <.icon name="hero-stop-micro" class="size-3" /> Stop
      </button>

      <%!-- Separator: 1px × 16px per Figma --%>
      <div class="w-px h-4 mx-1 shrink-0" style="background-color: var(--taniwha-actionbar-border)" />

      <button
        type="button"
        phx-click="bulk_remove"
        disabled={@selected_count == 0}
        aria-label="Remove selected torrents"
        class={[
          "inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded",
          @selected_count > 0 && "hover:bg-red-50 hover:text-red-600 cursor-pointer",
          @selected_count == 0 && "opacity-40 cursor-not-allowed"
        ]}
        style="color: var(--taniwha-col-header)"
      >
        <.icon name="hero-trash-micro" class="size-3" /> Remove
      </button>

      <button
        :if={@selected_count > 0}
        type="button"
        phx-click="deselect_all"
        aria-label="Deselect all torrents"
        class="inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded hover:bg-[#f3f4f6] cursor-pointer"
        style="color: var(--taniwha-col-header)"
      >
        Clear
      </button>

      <%!-- Selected count --%>
      <span
        :if={@selected_count > 0}
        class="text-[10px] ml-1"
        style="color: var(--taniwha-sidebar-active)"
      >
        {@selected_count} selected
      </span>

      <%!-- Spacer --%>
      <div class="flex-1" />

      <%!-- Count --%>
      <span class="text-[10px]" style="color: var(--taniwha-sidebar-section)">
        {@visible_count} torrents
      </span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # table_header/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the sticky `<tr>` table header row with sortable column headers.

  Each sortable column emits `phx-click="sort"` with `phx-value-by` set to the
  column key. The active sort column has `aria-sort` set to `"ascending"` or
  `"descending"`. A select-all checkbox appears in the leading cell.

  ## Attributes

  - `:sort_by` (required) — currently active sort column atom
  - `:sort_dir` (required) — `:asc` or `:desc`
  - `:all_selected?` — whether every visible row is selected, default `false`
  - `:total_visible` — count passed to select-all checkbox label, default 0

  ## Examples

      <.table_header sort_by={@sort_by} sort_dir={@sort_dir} all_selected?={false} total_visible={6} />
  """
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :all_selected?, :boolean, default: false
  attr :total_visible, :integer, default: 0

  def table_header(assigns) do
    ~H"""
    <tr
      class="border-b text-[11px] font-medium"
      style="background: var(--taniwha-table-header-bg); border-color: var(--taniwha-row-border); color: var(--taniwha-col-header)"
    >
      <%!-- Select-all checkbox --%>
      <th scope="col" class="w-8 px-3 py-0" style="height: var(--taniwha-actionbar-h)">
        <input
          type="checkbox"
          phx-click="select_all"
          checked={@all_selected?}
          aria-label={"Select all #{@total_visible} visible torrents"}
          class="size-3 rounded"
        />
      </th>

      <%!-- Name (sortable, grows) --%>
      <th scope="col" class="px-[6px] py-0 text-left" style="height: var(--taniwha-actionbar-h)">
        <.sort_header label="Name" column={:name} sort_by={@sort_by} sort_dir={@sort_dir} />
      </th>

      <%!-- Size (sortable, right-align) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-right"
        style="width: 143px; height: var(--taniwha-actionbar-h)"
      >
        <.sort_header
          label="Size"
          column={:size}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
          align={:right}
        />
      </th>

      <%!-- Progress (sortable) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-left"
        style="width: 182px; height: var(--taniwha-actionbar-h)"
      >
        <.sort_header
          label="Progress"
          column={:progress}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
        />
      </th>

      <%!-- Down (sortable, right-align) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-right"
        style="width: 130px; height: var(--taniwha-actionbar-h)"
      >
        <.sort_header
          label="Down"
          column={:speed}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
          align={:right}
        />
      </th>

      <%!-- Up (right-align) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-right"
        style="width: 130px; height: var(--taniwha-actionbar-h)"
      >
        Up
      </th>

      <%!-- Seeds (right-align) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-right"
        style="width: 91px; height: var(--taniwha-actionbar-h)"
      >
        Seeds
      </th>

      <%!-- Peers (right-align) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-right"
        style="width: 91px; height: var(--taniwha-actionbar-h)"
      >
        Peers
      </th>

      <%!-- Ratio (sortable, right-align) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-right"
        style="width: 91px; height: var(--taniwha-actionbar-h)"
      >
        <.sort_header
          label="Ratio"
          column={:ratio}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
          align={:right}
        />
      </th>

      <%!-- Status (sortable) --%>
      <th
        scope="col"
        class="px-[6px] py-0 text-left"
        style="width: 78px; height: var(--taniwha-actionbar-h)"
      >
        <.sort_header
          label="Status"
          column={:status}
          sort_by={@sort_by}
          sort_dir={@sort_dir}
        />
      </th>
    </tr>
    """
  end

  attr :label, :string, required: true
  attr :column, :atom, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :align, :atom, default: :left

  defp sort_header(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="sort"
      phx-value-by={to_string(@column)}
      aria-sort={aria_sort(@column, @sort_by, @sort_dir)}
      class={"inline-flex items-center gap-[2px] #{if @align == :right, do: "flex-row-reverse w-full", else: ""}"}
    >
      {@label}
      <.icon
        :if={@column == @sort_by}
        name={if @sort_dir == :asc, do: "hero-chevron-up-micro", else: "hero-chevron-down-micro"}
        class="size-[10px]"
      />
    </button>
    """
  end

  @spec aria_sort(atom(), atom(), atom()) :: String.t()
  defp aria_sort(col, col, :asc), do: "ascending"
  defp aria_sort(col, col, :desc), do: "descending"
  defp aria_sort(_col, _sort_by, _dir), do: "none"

  # ---------------------------------------------------------------------------
  # torrent_row/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a 28px table row (`<tr>`) with 9 data cells for a single torrent.

  Columns: Name, Size, Progress, Down, Up, Seeds (placeholder "—"), Peers,
  Ratio, Status. A leading checkbox cell supports row selection.

  ## Attributes

  - `:torrent` (required) — a `Taniwha.Torrent` struct
  - `:selected?` — whether this row is currently selected, default `false`
  - `:on_start` — event name for the start action
  - `:on_stop` — event name for the stop action
  - `:on_remove` — event name for the remove action

  ## Examples

      <.torrent_row
        :for={torrent <- visible}
        torrent={torrent}
        selected?={MapSet.member?(@selected_hashes, torrent.hash)}
        on_start="start_torrent"
        on_stop="stop_torrent"
        on_remove="remove_torrent"
      />
  """
  attr :torrent, :map, required: true
  attr :selected?, :boolean, default: false
  attr :row_selected?, :boolean, default: false
  attr :on_start, :any, default: nil
  attr :on_stop, :any, default: nil
  attr :on_remove, :any, default: nil

  def torrent_row(assigns) do
    assigns =
      assigns
      |> assign(:progress, Torrent.progress(assigns.torrent) * 100)
      |> assign(:status, Torrent.status(assigns.torrent))

    ~H"""
    <tr
      id={"torrent-#{@torrent.hash}"}
      aria-label={@torrent.name}
      phx-click="select_torrent"
      phx-value-hash={@torrent.hash}
      data-hash={@torrent.hash}
      class="border-b hover:bg-[#f9fafb] dark:hover:bg-[#1a1f2e] cursor-pointer"
      style={"height: var(--taniwha-row-h); border-color: var(--taniwha-row-border)#{if @row_selected?, do: "; background: var(--taniwha-sidebar-active-bg)", else: ""}"}
    >
      <td class="w-8 px-3">
        <input
          type="checkbox"
          phx-click="toggle_select"
          phx-value-hash={@torrent.hash}
          checked={@selected?}
          aria-label={"Select #{@torrent.name}"}
          class="size-3 rounded"
        />
      </td>

      <td class="px-[6px] overflow-hidden">
        <span
          class="block truncate text-[11px]"
          title={@torrent.name}
          style="color: var(--taniwha-cell-name)"
        >
          {@torrent.name}
        </span>
      </td>

      <td class="px-[6px] text-right text-[11px] tabular-nums" style="color: var(--taniwha-cell-num)">
        {format_bytes(@torrent.size)}
      </td>

      <td class="px-[6px]">
        <div class="flex items-center gap-[4px]">
          <span
            class="shrink-0 w-[28px] text-right text-[10px] tabular-nums"
            style="color: var(--taniwha-cell-pct)"
          >
            {trunc(@progress)}%
          </span>
          <div class="flex-1">
            <.progress_bar value={@progress} color={@status} />
          </div>
        </div>
      </td>

      <td class="px-[6px] text-right">
        <.speed_display bytes_per_second={@torrent.download_rate} direction={:down} />
      </td>

      <td class="px-[6px] text-right">
        <.speed_display bytes_per_second={@torrent.upload_rate} direction={:up} />
      </td>

      <%!-- Seeds (no data yet — placeholder) --%>
      <td
        class="px-[6px] text-right text-[11px] tabular-nums"
        style="color: var(--taniwha-cell-num)"
      >
        —
      </td>

      <td
        class="px-[6px] text-right text-[11px] tabular-nums"
        style="color: var(--taniwha-cell-num)"
      >
        {@torrent.peers_connected}
      </td>

      <td
        class="px-[6px] text-right text-[11px] tabular-nums"
        style="color: var(--taniwha-cell-num)"
      >
        {format_ratio(@torrent.ratio)}
      </td>

      <td class="px-[6px]">
        <div class="flex items-center gap-1">
          <.status_badge status={@status} />
          <button
            :if={@on_start && @status in [:stopped, :paused]}
            type="button"
            phx-click={@on_start}
            phx-value-hash={@torrent.hash}
            aria-label={"Start #{@torrent.name}"}
            class="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-[#dcfce7] hover:text-[#15803d]"
            style="color: var(--taniwha-col-header)"
          >
            <.icon name="hero-play-micro" class="size-3" />
          </button>
          <button
            :if={@on_stop && @status in [:downloading, :seeding, :checking]}
            type="button"
            phx-click={@on_stop}
            phx-value-hash={@torrent.hash}
            aria-label={"Stop #{@torrent.name}"}
            class="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-[#f3f4f6]"
            style="color: var(--taniwha-col-header)"
          >
            <.icon name="hero-stop-micro" class="size-3" />
          </button>
          <button
            type="button"
            phx-click={@on_remove}
            phx-value-hash={@torrent.hash}
            aria-label={"Remove #{@torrent.name}"}
            class="ml-auto opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-[#fee2e2] hover:text-[#991b1b]"
            style="color: var(--taniwha-col-header)"
          >
            <.icon name="hero-trash-micro" class="size-3" />
          </button>
        </div>
      </td>
    </tr>
    """
  end

  # ---------------------------------------------------------------------------
  # torrent_table/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the full torrent table: sticky header row, data rows, and empty states.

  Accepts a pre-filtered and pre-sorted list of torrents from the LiveView.
  The component computes `all_selected?` internally from `:total_visible` and `:selected_hashes`.

  ## Attributes

  - `:torrents` (required) — filtered+sorted list of `Taniwha.Torrent` structs
  - `:all_torrents_empty?` (required) — `true` when the ETS store is empty (used to
    distinguish "no torrents at all" from "no results after filtering")
  - `:sort_by` (required) — active sort column atom
  - `:sort_dir` (required) — `:asc` or `:desc`
  - `:selected_hashes` (required) — `MapSet` of hash strings for bulk selection
  - `:total_visible` (required) — count of visible torrents (pass `length(visible)` from template)
  - `:selected_hash` — hash string of the row-clicked torrent (opens detail panel),
    or `nil`. Defaults to `nil`.
  - `:on_start`, `:on_stop`, `:on_remove` — event name strings passed to each row

  ## Examples

      <.torrent_table
        torrents={visible}
        all_torrents_empty?={@torrents == []}
        sort_by={@sort_by}
        sort_dir={@sort_dir}
        selected_hashes={@selected_hashes}
        total_visible={visible_count}
        selected_hash={@selected_hash}
        on_start="start_torrent"
        on_stop="stop_torrent"
        on_remove="remove_torrent"
      />
  """
  attr :torrents, :list, required: true
  attr :all_torrents_empty?, :boolean, required: true
  attr :sort_by, :atom, required: true
  attr :sort_dir, :atom, required: true
  attr :selected_hashes, :any, required: true
  attr :total_visible, :integer, required: true
  attr :selected_hash, :any, default: nil
  attr :on_start, :string, default: nil
  attr :on_stop, :string, default: nil
  attr :on_remove, :string, default: nil

  def torrent_table(assigns) do
    all_selected? =
      assigns.total_visible > 0 and MapSet.size(assigns.selected_hashes) == assigns.total_visible

    assigns = assign(assigns, :all_selected?, all_selected?)

    ~H"""
    <div class="min-h-0 flex-1 overflow-y-auto">
      <table class="w-full border-collapse table-fixed">
        <thead class="sticky top-0 z-10">
          <.table_header
            sort_by={@sort_by}
            sort_dir={@sort_dir}
            all_selected?={@all_selected?}
            total_visible={@total_visible}
          />
        </thead>
        <tbody phx-hook=".ContextMenu" id="torrent-tbody">
          <%!-- Empty state: no torrents at all --%>
          <tr :if={@torrents == [] and @all_torrents_empty?}>
            <td
              colspan="10"
              class="py-16 text-center text-[11px]"
              style="color: var(--taniwha-col-header)"
              role="status"
              aria-label="No torrents"
            >
              <p class="mb-2">No torrents yet.</p>
              <.link navigate={~p"/add"} class="text-[#2563eb] hover:underline">
                Add your first torrent
              </.link>
            </td>
          </tr>

          <%!-- Empty state: filters active but nothing matches --%>
          <tr :if={@torrents == [] and not @all_torrents_empty?}>
            <td
              colspan="10"
              class="py-8 text-center text-[11px]"
              style="color: var(--taniwha-col-header)"
              role="status"
              aria-label="No results"
            >
              No torrents match your search or filter.
            </td>
          </tr>

          <%!-- Torrent rows --%>
          <.torrent_row
            :for={torrent <- @torrents}
            torrent={torrent}
            selected?={MapSet.member?(@selected_hashes, torrent.hash)}
            row_selected?={@selected_hash == torrent.hash}
            on_start={@on_start}
            on_stop={@on_stop}
            on_remove={@on_remove}
          />
        </tbody>
      </table>
    </div>

    <script :type={ColocatedHook} name=".ContextMenu">
      const MENU_WIDTH = 208;
      const ITEM_HEIGHT = 28;

      const MENU_ITEMS = [
        { action: "start",  label: "Start",       destructive: false },
        { action: "pause",  label: "Pause",       destructive: false },
        { action: "stop",   label: "Stop",        destructive: false },
        { separator: true },
        { action: "copy_hash", label: "Copy hash", client: true, destructive: false },
        { separator: true },
        { action: "erase",  label: "Remove",      destructive: true  },
      ];

      function buildMenu(hash) {
        const menu = document.createElement("div");
        menu.setAttribute("role", "menu");
        menu.setAttribute("aria-label", "Torrent actions");
        menu.style.cssText = [
          "position:fixed",
          `width:${MENU_WIDTH}px`,
          "z-index:9999",
          "padding:4px",
          "border-radius:8px",
          "border:1px solid var(--taniwha-row-border,#e5e7eb)",
          "background:var(--taniwha-bg,#fff)",
          "box-shadow:0 10px 30px rgba(0,0,0,0.15)",
          "outline:none",
        ].join(";");

        const focusable = [];

        MENU_ITEMS.forEach((item) => {
          if (item.separator) {
            const sep = document.createElement("div");
            sep.setAttribute("role", "separator");
            sep.style.cssText = "margin:4px 0;border-top:1px solid var(--taniwha-row-border,#f3f4f6)";
            menu.appendChild(sep);
            return;
          }

          const btn = document.createElement("button");
          btn.setAttribute("role", "menuitem");
          btn.setAttribute("data-action", item.action);
          btn.setAttribute("type", "button");
          btn.style.cssText = [
            "display:block",
            "width:100%",
            "text-align:left",
            "padding:6px 12px",
            "font-size:11px",
            "border-radius:6px",
            "border:none",
            "cursor:pointer",
            "background:transparent",
            item.destructive
              ? "color:var(--taniwha-destructive,#ef4444)"
              : "color:var(--taniwha-text,#374151)",
          ].join(";");
          btn.textContent = item.label;

          menu.appendChild(btn);
          focusable.push(btn);
        });

        return { menu, focusable };
      }

      export default {
        _cleanup: null,

        mounted() {
          this._onContextMenu = (e) => {
            const row = e.target.closest("tr[data-hash]");
            if (!row) return;
            e.preventDefault();

            const hash = row.dataset.hash;
            this._openMenu(e.clientX, e.clientY, hash);
          };

          this.el.addEventListener("contextmenu", this._onContextMenu);
        },

        destroyed() {
          this.el.removeEventListener("contextmenu", this._onContextMenu);
          this._closeMenu();
        },

        _openMenu(x, y, hash) {
          this._closeMenu();

          const { menu, focusable } = buildMenu(hash);

          // Position with viewport clamping
          const vw = window.innerWidth;
          const vh = window.innerHeight;
          const estimatedH = MENU_ITEMS.length * ITEM_HEIGHT + 8;
          const left = x + MENU_WIDTH > vw ? vw - MENU_WIDTH - 8 : x;
          const top  = y + estimatedH  > vh ? vh - estimatedH - 8 : y;
          menu.style.left = left + "px";
          menu.style.top  = top  + "px";

          let focusIdx = 0;

          const close = () => {
            menu.remove();
            document.removeEventListener("keydown", onKey, true);
            document.removeEventListener("mousedown", onOutside, true);
            this._cleanup = null;
          };

          const onKey = (e) => {
            if (e.key === "Escape") { close(); return; }
            if (e.key === "ArrowDown") {
              e.preventDefault();
              focusIdx = (focusIdx + 1) % focusable.length;
              focusable[focusIdx].focus();
            } else if (e.key === "ArrowUp") {
              e.preventDefault();
              focusIdx = (focusIdx - 1 + focusable.length) % focusable.length;
              focusable[focusIdx].focus();
            } else if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              focusable[focusIdx].click();
            }
          };

          const onOutside = (e) => {
            if (!menu.contains(e.target)) close();
          };

          menu.addEventListener("click", (e) => {
            const btn = e.target.closest("button[data-action]");
            if (!btn) return;
            const action = btn.dataset.action;

            if (action === "copy_hash") {
              navigator.clipboard.writeText(hash).catch(() => {});
            } else {
              this.pushEvent("context_menu_action", { action, hash });
            }
            close();
          });

          document.body.appendChild(menu);
          document.addEventListener("keydown", onKey, true);
          document.addEventListener("mousedown", onOutside, true);
          this._cleanup = close;

          // Focus first item
          requestAnimationFrame(() => {
            if (focusable.length > 0) focusable[0].focus();
          });
        },

        _closeMenu() {
          if (this._cleanup) this._cleanup();
        },
      };
    </script>
    """
  end
end
