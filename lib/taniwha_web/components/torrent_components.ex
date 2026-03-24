defmodule TaniwhaWeb.TorrentComponents do
  @moduledoc """
  Reusable LiveView function components for the Taniwha torrent management UI.

  All components follow WCAG 2.2 AA accessibility guidelines: correct ARIA
  roles, labels, and semantic HTML. Import this module in your LiveViews and
  templates with:

      import TaniwhaWeb.TorrentComponents

  ## Components

  - `progress_bar/1` — 3px animated progress indicator with ARIA role
  - `status_badge/1` — compact pill with coloured dot and abbreviated label
  - `speed_display/1` — human-readable transfer speed with directional icon
  - `topbar/1` — 40px app header with logo, search, global stats, add button
  - `sidebar/1` — 140px navigation with status/tracker/label filters
  - `action_bar/1` — 32px bulk-action toolbar with torrent count
  - `table_header/1` — sticky `<tr>` with sortable column headers
  - `torrent_row/1` — 28px table row with 9 cells for a single torrent
  """

  use TaniwhaWeb, :html

  import TaniwhaWeb.FormatHelpers, only: [format_bytes: 1, format_speed: 1]

  alias Taniwha.Torrent

  # ---------------------------------------------------------------------------
  # progress_bar/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a 3px horizontal progress bar with ARIA `progressbar` role.

  Uses CSS custom properties (`--taniwha-status-*-bar`) for colours so that
  the progress bar adapts to light/dark mode automatically.

  ## Attributes

  - `:value` (required) — float between 0.0 and 100.0 representing percentage
  - `:color` — atom matching a torrent status: `:downloading`, `:seeding`,
    `:stopped`, `:paused`, `:checking`. Defaults to `:downloading`.
  - `:id` — optional HTML id attribute

  ## Examples

      <.progress_bar value={45.5} color={:seeding} />
      <.progress_bar value={@torrent |> Torrent.progress() |> Kernel.*(100)} color={:downloading} />
  """
  attr :value, :float, required: true
  attr :color, :atom, default: :downloading
  attr :id, :string, default: nil
  attr :rest, :global

  def progress_bar(assigns) do
    ~H"""
    <div
      id={@id}
      role="progressbar"
      aria-valuenow={round(@value)}
      aria-valuemin="0"
      aria-valuemax="100"
      class="w-full bg-[#f3f4f6] dark:bg-[#1f2937] rounded-full h-[3px]"
      {@rest}
    >
      <div
        class="h-[3px] rounded-full transition-all"
        style={"width: #{@value}%; background-color: var(#{progress_bar_css_var(@color)})"}
      />
    </div>
    """
  end

  @spec progress_bar_css_var(atom()) :: String.t()
  defp progress_bar_css_var(status), do: "--taniwha-status-#{status_slug(status)}-bar"

  # ---------------------------------------------------------------------------
  # status_badge/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a compact badge pill with a coloured dot and abbreviated status label.

  ## Attributes

  - `:status` (required) — one of `:downloading`, `:seeding`, `:stopped`,
    `:paused`, `:checking`, `:unknown`

  ## Examples

      <.status_badge status={Torrent.status(@torrent)} />
  """
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-[3px] px-[6px] py-[1px] rounded-[4px] text-[10px] font-medium leading-[15px]"
      style={"background-color: var(#{badge_bg_var(@status)}); color: var(#{badge_text_var(@status)})"}
    >
      <span
        class="size-[6px] rounded-[3px] shrink-0"
        style={"background-color: var(#{badge_dot_var(@status)})"}
        aria-hidden="true"
      />
      {badge_label(@status)}
    </span>
    """
  end

  @spec status_slug(atom()) :: String.t()
  defp status_slug(:downloading), do: "dl"
  defp status_slug(:seeding), do: "seed"
  defp status_slug(:stopped), do: "stop"
  defp status_slug(:paused), do: "stop"
  defp status_slug(:checking), do: "check"
  defp status_slug(_), do: "err"

  @spec badge_bg_var(atom()) :: String.t()
  defp badge_bg_var(status), do: "--taniwha-status-#{status_slug(status)}-badge-bg"

  @spec badge_text_var(atom()) :: String.t()
  defp badge_text_var(status), do: "--taniwha-status-#{status_slug(status)}-badge-text"

  @spec badge_dot_var(atom()) :: String.t()
  defp badge_dot_var(status), do: "--taniwha-status-#{status_slug(status)}-dot"

  @spec badge_label(atom()) :: String.t()
  defp badge_label(:downloading), do: "DL"
  defp badge_label(:seeding), do: "Seed"
  defp badge_label(:stopped), do: "Stop"
  defp badge_label(:paused), do: "Pause"
  defp badge_label(:checking), do: "Check"
  defp badge_label(_), do: "Unknown"

  # ---------------------------------------------------------------------------
  # speed_display/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a human-readable transfer speed with an optional directional icon.

  Automatically scales to B/s, KB/s, MB/s, or GB/s. Uses
  `--taniwha-speed-dl` / `--taniwha-speed-ul` CSS variables for colour when a
  direction is provided.

  ## Attributes

  - `:bytes_per_second` (required) — non-negative integer
  - `:direction` — `:up` renders `hero-arrow-up-micro`;
    `:down` renders `hero-arrow-down-micro`; `nil` renders no icon

  ## Examples

      <.speed_display bytes_per_second={@torrent.download_rate} direction={:down} />
      <.speed_display bytes_per_second={@torrent.upload_rate} direction={:up} />
  """
  attr :bytes_per_second, :integer, required: true
  attr :direction, :atom, default: nil

  def speed_display(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-0.5 tabular-nums text-[11px]"
      style={speed_color_style(@direction)}
    >
      <.icon :if={@direction == :up} name="hero-arrow-up-micro" class="size-3 shrink-0" />
      <.icon :if={@direction == :down} name="hero-arrow-down-micro" class="size-3 shrink-0" />
      {format_speed(@bytes_per_second)}
    </span>
    """
  end

  @spec speed_color_style(atom() | nil) :: String.t()
  defp speed_color_style(:down), do: "color: var(--taniwha-speed-dl)"
  defp speed_color_style(:up), do: "color: var(--taniwha-speed-ul)"
  defp speed_color_style(_), do: ""

  # ---------------------------------------------------------------------------
  # topbar/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the 40px application topbar with logo, search, global transfer stats,
  and the Add torrent button.

  The global stats region uses `role="status"` so screen readers announce rate
  changes when PubSub pushes updates. The search input is wrapped in a
  `<search>` landmark with a visually-hidden label for accessibility.

  ## Attributes

  - `:upload_rate` — integer bytes/s, default 0
  - `:download_rate` — integer bytes/s, default 0
  - `:search` — current search string, default `""`

  ## Examples

      <.topbar
        upload_rate={@global_upload_rate}
        download_rate={@global_download_rate}
        search={@search}
      />
  """
  attr :upload_rate, :integer, default: 0
  attr :download_rate, :integer, default: 0
  attr :search, :string, default: ""

  def topbar(assigns) do
    ~H"""
    <header
      class="flex items-center gap-3 px-3 border-b shrink-0"
      style="height: var(--taniwha-topbar-h); background: var(--taniwha-topbar-bg); border-color: var(--taniwha-topbar-border)"
    >
      <%!-- Logo --%>
      <span
        class="font-bold text-[13px] tracking-[-0.02em] shrink-0"
        style="color: var(--taniwha-logo)"
      >
        Taniwha
      </span>

      <%!-- Search --%>
      <search class="relative shrink-0" style="width: 200px">
        <label for="topbar-search" class="sr-only">Search torrents</label>
        <span
          class="absolute left-2 top-1/2 -translate-y-1/2 pointer-events-none"
          style="color: var(--taniwha-sidebar-section)"
          aria-hidden="true"
        >
          <.icon name="hero-magnifying-glass-micro" class="size-3" />
        </span>
        <input
          id="topbar-search"
          type="search"
          name="search"
          value={@search}
          placeholder="Search torrents..."
          phx-change="search"
          phx-debounce="200"
          autocomplete="off"
          class="w-full h-[24px] pl-[26px] pr-2 rounded-[6px] text-[11px] border outline-none focus:outline-none"
          style="background: var(--taniwha-search-bg); border-color: var(--taniwha-search-border); color: var(--taniwha-cell-name)"
        />
      </search>

      <%!-- Spacer --%>
      <div class="flex-1" />

      <%!-- Global transfer stats --%>
      <div
        role="status"
        aria-label="Global transfer statistics"
        class="flex items-center gap-3"
      >
        <.speed_display bytes_per_second={@download_rate} direction={:down} />
        <.speed_display bytes_per_second={@upload_rate} direction={:up} />
      </div>

      <%!-- Separator --%>
      <div class="w-px h-4" style="background: var(--taniwha-topbar-border)" />

      <%!-- Add torrent button --%>
      <.link
        navigate={~p"/add"}
        class="inline-flex items-center gap-[6px] h-[24px] px-[10px] rounded-[6px] bg-[#2563eb] text-white text-[11px] font-medium shrink-0"
        aria-label="Add torrent"
      >
        <.icon name="hero-plus-micro" class="size-3" /> Add torrent
      </.link>

      <%!-- Theme toggle --%>
      <TaniwhaWeb.Layouts.theme_toggle />
    </header>
    """
  end

  # ---------------------------------------------------------------------------
  # sidebar/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the 140px fixed sidebar navigation with status, tracker, and label filters.

  Each filter item is a `<button>` with `aria-pressed` set to `"true"` when
  active, `"false"` otherwise. The `phx-click` events update the LiveView
  assigns to re-filter the torrent table.

  ## Attributes

  - `:filter` (required) — active status filter atom: `:all`, `:downloading`,
    `:seeding`, `:stopped`, `:checking`
  - `:tracker_filter` (required) — active tracker filter: `:all` or a domain
    string
  - `:status_counts` (required) — map with keys `:all`, `:downloading`,
    `:seeding`, `:stopped`, `:checking`, `:paused`
  - `:tracker_groups` — list of `{domain, count}` tuples, default `[]`

  ## Examples

      <.sidebar
        filter={@filter}
        tracker_filter={@tracker_filter}
        status_counts={@status_counts}
        tracker_groups={@tracker_groups}
      />
  """
  attr :filter, :atom, required: true
  attr :tracker_filter, :any, required: true
  attr :status_counts, :map, required: true
  attr :tracker_groups, :list, default: []

  def sidebar(assigns) do
    ~H"""
    <nav
      aria-label="Torrent filters"
      class="flex flex-col shrink-0 border-r overflow-y-auto"
      style="width: var(--taniwha-sidebar-w); background: var(--taniwha-sidebar-bg); border-color: var(--taniwha-sidebar-border)"
    >
      <%!-- Status section --%>
      <div class="pt-2">
        <p
          class="px-3 pb-1 text-[10px] font-semibold tracking-[0.08em] uppercase"
          style="color: var(--taniwha-sidebar-section)"
        >
          Status
        </p>

        <.sidebar_filter_item
          label="All"
          value="all"
          active?={@filter == :all}
          count={Map.get(@status_counts, :all, 0)}
          dot_color={status_dot_color(:all)}
          event="filter"
        />
        <.sidebar_filter_item
          label="Downloading"
          value="downloading"
          active?={@filter == :downloading}
          count={Map.get(@status_counts, :downloading, 0)}
          dot_color={status_dot_color(:downloading)}
          event="filter"
        />
        <.sidebar_filter_item
          label="Seeding"
          value="seeding"
          active?={@filter == :seeding}
          count={Map.get(@status_counts, :seeding, 0)}
          dot_color={status_dot_color(:seeding)}
          event="filter"
        />
        <.sidebar_filter_item
          label="Stopped"
          value="stopped"
          active?={@filter == :stopped}
          count={Map.get(@status_counts, :stopped, 0)}
          dot_color={status_dot_color(:stopped)}
          event="filter"
        />
        <.sidebar_filter_item
          label="Checking"
          value="checking"
          active?={@filter == :checking}
          count={Map.get(@status_counts, :checking, 0)}
          dot_color={status_dot_color(:checking)}
          event="filter"
        />
      </div>

      <%!-- Divider --%>
      <div class="mx-3 my-1 border-t" style="border-color: var(--taniwha-sidebar-border)" />

      <%!-- Trackers section --%>
      <%!-- TODO: populate once Torrent struct exposes tracker URLs --%>
      <div>
        <p
          class="px-3 pb-1 text-[10px] font-semibold tracking-[0.08em] uppercase"
          style="color: var(--taniwha-sidebar-section)"
        >
          Trackers
        </p>

        <.sidebar_filter_item
          :for={{domain, count} <- @tracker_groups}
          label={domain}
          value={domain}
          active?={@tracker_filter == domain}
          count={count}
          event="filter_tracker"
        />
      </div>

      <%!-- Divider --%>
      <div class="mx-3 my-1 border-t" style="border-color: var(--taniwha-sidebar-border)" />

      <%!-- Labels section --%>
      <div>
        <p
          class="px-3 pb-1 text-[10px] font-semibold tracking-[0.08em] uppercase"
          style="color: var(--taniwha-sidebar-section)"
        >
          Labels
        </p>
        <p
          class="px-3 py-1 text-[10px] italic"
          style="color: var(--taniwha-sidebar-section)"
        >
          No labels yet
        </p>
      </div>
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :active?, :boolean, required: true
  attr :count, :integer, required: true
  attr :event, :string, required: true
  attr :dot_color, :string, default: nil

  defp sidebar_filter_item(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-value={@value}
      aria-pressed={to_string(@active?)}
      class="flex items-center gap-2 w-full px-3 h-[27px] text-[11px] text-left"
      style={sidebar_item_style(@active?)}
    >
      <span
        :if={@dot_color}
        class="size-[6px] rounded-[3px] shrink-0"
        style={"background-color: #{@dot_color}"}
        aria-hidden="true"
      />
      <span class="flex-1 min-w-0 truncate">{@label}</span>
      <span
        class="shrink-0 px-[6px] h-[17px] rounded-full text-[10px] leading-[17px]"
        style="background-color: var(--taniwha-actionbar-border); color: var(--taniwha-sidebar-section)"
      >
        {@count}
      </span>
    </button>
    """
  end

  @spec sidebar_item_style(boolean()) :: String.t()
  defp sidebar_item_style(true),
    do:
      "background-color: var(--taniwha-sidebar-active-bg); color: var(--taniwha-sidebar-active); font-weight: 500"

  defp sidebar_item_style(false),
    do: "color: var(--taniwha-sidebar-inactive)"

  @spec status_dot_color(:all | :downloading | :seeding | :stopped | :checking) :: String.t()
  defp status_dot_color(:all), do: "var(--taniwha-sidebar-section)"
  defp status_dot_color(status), do: "var(--taniwha-status-#{status_slug(status)}-dot)"

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
        class="inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded hover:bg-[#f3f4f6]"
        style="color: var(--taniwha-col-header)"
      >
        <.icon name="hero-play-micro" class="size-3" /> Start
      </button>

      <button
        type="button"
        phx-click="bulk_stop"
        class="inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded hover:bg-[#f3f4f6]"
        style="color: var(--taniwha-col-header)"
      >
        <.icon name="hero-stop-micro" class="size-3" /> Stop
      </button>

      <button
        :if={@selected_count > 0}
        type="button"
        phx-click="deselect_all"
        aria-label="Deselect all torrents"
        class="inline-flex items-center gap-1 h-[22px] px-2 text-[11px] rounded hover:bg-[#f3f4f6]"
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
      class="border-b hover:bg-[#f9fafb] dark:hover:bg-[#1a1f2e] cursor-pointer"
      style={"height: var(--taniwha-row-h); border-color: var(--taniwha-row-border)#{if @row_selected?, do: "; background: var(--taniwha-sidebar-active-bg)", else: ""}"}
    >
      <%!-- Checkbox --%>
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

      <%!-- Name --%>
      <td class="px-[6px] overflow-hidden">
        <span
          class="block truncate text-[11px]"
          title={@torrent.name}
          style="color: var(--taniwha-cell-name)"
        >
          {@torrent.name}
        </span>
      </td>

      <%!-- Size --%>
      <td class="px-[6px] text-right text-[11px] tabular-nums" style="color: var(--taniwha-cell-num)">
        {format_bytes(@torrent.size)}
      </td>

      <%!-- Progress --%>
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

      <%!-- Down --%>
      <td class="px-[6px] text-right">
        <.speed_display bytes_per_second={@torrent.download_rate} direction={:down} />
      </td>

      <%!-- Up --%>
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

      <%!-- Peers --%>
      <td
        class="px-[6px] text-right text-[11px] tabular-nums"
        style="color: var(--taniwha-cell-num)"
      >
        {@torrent.peers_connected}
      </td>

      <%!-- Ratio --%>
      <td
        class="px-[6px] text-right text-[11px] tabular-nums"
        style="color: var(--taniwha-cell-num)"
      >
        {Float.round(@torrent.ratio, 2)}
      </td>

      <%!-- Status + action buttons --%>
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
  The component computes `all_selected?` and `total_visible` internally.

  ## Attributes

  - `:torrents` (required) — filtered+sorted list of `Taniwha.Torrent` structs
  - `:all_torrents_empty?` (required) — `true` when the ETS store is empty (used to
    distinguish "no torrents at all" from "no results after filtering")
  - `:sort_by` (required) — active sort column atom
  - `:sort_dir` (required) — `:asc` or `:desc`
  - `:selected_hashes` (required) — `MapSet` of hash strings for bulk selection
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
  attr :selected_hash, :any, default: nil
  attr :on_start, :string, default: nil
  attr :on_stop, :string, default: nil
  attr :on_remove, :string, default: nil

  def torrent_table(assigns) do
    total_visible = length(assigns.torrents)
    all_selected? = total_visible > 0 and MapSet.size(assigns.selected_hashes) == total_visible

    assigns =
      assigns
      |> assign(:total_visible, total_visible)
      |> assign(:all_selected?, all_selected?)

    ~H"""
    <div class="flex-1 overflow-y-auto">
      <table class="w-full border-collapse table-fixed">
        <thead class="sticky top-0 z-10">
          <.table_header
            sort_by={@sort_by}
            sort_dir={@sort_dir}
            all_selected?={@all_selected?}
            total_visible={@total_visible}
          />
        </thead>
        <tbody>
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
    """
  end
end
