defmodule TaniwhaWeb.TorrentComponents.LayoutComponents do
  @moduledoc """
  Full-page layout components: the application topbar and sidebar navigation.
  """

  use TaniwhaWeb, :html

  import TaniwhaWeb.TorrentComponents.StatusComponents, only: [speed_display: 1]

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
      <button
        type="button"
        phx-click="show_add_modal"
        class="inline-flex items-center gap-[6px] h-[24px] px-[10px] rounded-[6px] bg-[#2563eb] text-white text-[11px] font-medium shrink-0 cursor-pointer hover:bg-blue-700"
        aria-label="Add torrent"
      >
        <.icon name="hero-plus-micro" class="size-3" /> Add torrent
      </button>

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

  defp status_dot_color(status) do
    slug =
      case status do
        :downloading -> "dl"
        :seeding -> "seed"
        :stopped -> "stop"
        :checking -> "check"
        _ -> "err"
      end

    "var(--taniwha-status-#{slug}-dot)"
  end
end
