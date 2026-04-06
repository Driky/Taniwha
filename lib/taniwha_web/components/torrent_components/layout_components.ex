defmodule TaniwhaWeb.TorrentComponents.LayoutComponents do
  @moduledoc """
  Full-page layout components: the application topbar and sidebar navigation.
  """

  use TaniwhaWeb, :html

  import TaniwhaWeb.TorrentComponents.StatusComponents, only: [speed_display: 1, status_slug: 1]
  import TaniwhaWeb.TorrentComponents.ThrottleComponents, only: [throttle_context_menu: 1]
  import TaniwhaWeb.FormatHelpers, only: [format_speed: 1]

  alias Phoenix.LiveView.ColocatedHook

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
        current_user={@current_user}
      />
  """
  attr :upload_rate, :integer, default: 0
  attr :download_rate, :integer, default: 0
  attr :search, :string, default: ""
  attr :current_user, :map, default: nil
  attr :download_limit, :integer, default: 0
  attr :upload_limit, :integer, default: 0
  attr :presets, :list, default: []
  attr :throttle_menu, :any, default: nil
  attr :custom_input, :boolean, default: false

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

      <%!-- Global transfer stats with bandwidth limit controls --%>
      <div role="status" aria-label="Global transfer statistics" class="flex items-center gap-3">
        <%!-- Download speed indicator --%>
        <div
          class="relative"
          id="throttle-dl-indicator"
          phx-hook="ThrottleMenu"
          data-direction="download"
        >
          <button
            type="button"
            phx-click="open_throttle_menu"
            phx-value-direction="download"
            aria-haspopup="true"
            aria-expanded={to_string(@throttle_menu == :download)}
            aria-label={dl_indicator_label(@download_rate, @download_limit)}
            class={[
              "flex items-center gap-1 cursor-context-menu px-1 py-0.5 rounded",
              @throttle_menu == :download && "bg-gray-100 dark:bg-gray-800"
            ]}
          >
            <.speed_display bytes_per_second={@download_rate} direction={:down} />
            <span
              :if={@download_limit > 0}
              class="text-[10px] font-normal text-gray-400 dark:text-gray-500"
            >
              [{Taniwha.ThrottleStore.bytes_to_display(@download_limit)}]
            </span>
          </button>
          <.throttle_context_menu
            :if={@throttle_menu == :download}
            direction={:download}
            current_limit={@download_limit}
            presets={@presets}
            custom_input={@custom_input}
          />
        </div>

        <%!-- Upload speed indicator --%>
        <div
          class="relative"
          id="throttle-ul-indicator"
          phx-hook="ThrottleMenu"
          data-direction="upload"
        >
          <button
            type="button"
            phx-click="open_throttle_menu"
            phx-value-direction="upload"
            aria-haspopup="true"
            aria-expanded={to_string(@throttle_menu == :upload)}
            aria-label={ul_indicator_label(@upload_rate, @upload_limit)}
            class={[
              "flex items-center gap-1 cursor-context-menu px-1 py-0.5 rounded",
              @throttle_menu == :upload && "bg-gray-100 dark:bg-gray-800"
            ]}
          >
            <.speed_display bytes_per_second={@upload_rate} direction={:up} />
            <span
              :if={@upload_limit > 0}
              class="text-[10px] font-normal text-gray-400 dark:text-gray-500"
            >
              [{Taniwha.ThrottleStore.bytes_to_display(@upload_limit)}]
            </span>
          </button>
          <.throttle_context_menu
            :if={@throttle_menu == :upload}
            direction={:upload}
            current_limit={@upload_limit}
            presets={@presets}
            custom_input={@custom_input}
          />
        </div>
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

      <%!-- User menu --%>
      <.user_menu :if={@current_user} username={@current_user.username} />
    </header>
    """
  end

  # ---------------------------------------------------------------------------
  # user_menu/1
  # ---------------------------------------------------------------------------

  # Renders the 26px avatar circle and dropdown for the authenticated user.
  # The dropdown is toggled by the UserMenu JS hook (click-outside aware).
  # Sign out submits a hidden DELETE /session form to avoid a full navigation.
  attr :username, :string, required: true

  defp user_menu(assigns) do
    ~H"""
    <div class="relative shrink-0" id="user-menu-container" phx-hook="UserMenu">
      <%!-- Avatar circle --%>
      <button
        type="button"
        id="user-menu-button"
        aria-label="User menu"
        aria-haspopup="true"
        aria-expanded="false"
        class="flex items-center justify-center rounded-full text-[11px] font-semibold cursor-pointer border-none"
        style="width: 26px; height: 26px; background: var(--taniwha-avatar-bg, #e0e7ff); color: var(--taniwha-avatar-text, #4338ca);"
      >
        {String.first(@username) |> String.upcase()}
      </button>

      <%!-- Dropdown (hidden until toggled by UserMenu hook) --%>
      <div
        id="user-menu-dropdown"
        role="menu"
        aria-labelledby="user-menu-button"
        class="absolute right-0 mt-1 rounded-lg border shadow-lg z-50 hidden"
        style="min-width: 160px; background: var(--taniwha-topbar-bg); border-color: var(--taniwha-topbar-border); top: 100%;"
      >
        <%!-- Username display row --%>
        <div
          class="px-3 py-2 text-[11px] border-b"
          style="color: var(--taniwha-sidebar-section); border-color: var(--taniwha-topbar-border);"
        >
          {@username}
        </div>
        <%!-- Settings link --%>
        <a
          href={~p"/settings"}
          role="menuitem"
          class="block px-3 py-2 text-[12px] hover:bg-black/5"
          style="color: var(--taniwha-cell-name);"
        >
          Settings
        </a>
        <%!-- Sign out form (uses DELETE method override) --%>
        <form
          action={~p"/session"}
          method="post"
          class="border-t"
          style="border-color: var(--taniwha-topbar-border);"
        >
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <button
            type="submit"
            role="menuitem"
            class="w-full text-left px-3 py-2 text-[12px] hover:bg-black/5 cursor-pointer border-none bg-transparent"
            style="color: var(--taniwha-cell-name);"
          >
            Sign out
          </button>
        </form>
      </div>
    </div>
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
  attr :filter, :any, required: true
  attr :tracker_filter, :any, required: true
  attr :status_counts, :map, required: true
  attr :tracker_groups, :list, default: []
  attr :label_filter, :any, default: nil
  attr :label_groups, :list, default: []

  def sidebar(assigns) do
    ~H"""
    <nav
      id="sidebar-nav"
      aria-label="Torrent filters"
      phx-hook=".SidebarFilter"
      class="flex flex-col shrink-0 border-r overflow-y-auto"
      style="width: var(--taniwha-sidebar-w); background: var(--taniwha-sidebar-bg); border-color: var(--taniwha-sidebar-border)"
    >
      <%!-- Status section --%>
      <div class="pt-2" data-filter-section="status">
        <button
          type="button"
          data-collapse-toggle
          class="flex items-center justify-between w-full px-3 pb-1 pt-0"
          style="color: var(--taniwha-sidebar-section)"
        >
          <span class="text-[10px] font-semibold tracking-[0.08em] uppercase">Status</span>
          <svg
            data-collapse-icon
            class="w-3 h-3 transition-transform duration-150"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div data-section-content>
          <.sidebar_filter_item
            label="All"
            value="all"
            active?={Enum.empty?(@filter)}
            count={Map.get(@status_counts, :all, 0)}
            dot_color={status_dot_color(:all)}
          />
          <.sidebar_filter_item
            label="Downloading"
            value="downloading"
            active?={MapSet.member?(@filter, :downloading)}
            count={Map.get(@status_counts, :downloading, 0)}
            dot_color={status_dot_color(:downloading)}
          />
          <.sidebar_filter_item
            label="Seeding"
            value="seeding"
            active?={MapSet.member?(@filter, :seeding)}
            count={Map.get(@status_counts, :seeding, 0)}
            dot_color={status_dot_color(:seeding)}
          />
          <.sidebar_filter_item
            label="Stopped"
            value="stopped"
            active?={MapSet.member?(@filter, :stopped)}
            count={Map.get(@status_counts, :stopped, 0)}
            dot_color={status_dot_color(:stopped)}
          />
          <.sidebar_filter_item
            label="Checking"
            value="checking"
            active?={MapSet.member?(@filter, :checking)}
            count={Map.get(@status_counts, :checking, 0)}
            dot_color={status_dot_color(:checking)}
          />
        </div>
      </div>

      <%!-- Divider --%>
      <div class="mx-3 my-1 border-t" style="border-color: var(--taniwha-sidebar-border)" />

      <%!-- Labels section --%>
      <div data-filter-section="labels">
        <button
          type="button"
          data-collapse-toggle
          class="flex items-center justify-between w-full px-3 pb-1 pt-0"
          style="color: var(--taniwha-sidebar-section)"
        >
          <span class="text-[10px] font-semibold tracking-[0.08em] uppercase">Labels</span>
          <svg
            data-collapse-icon
            class="w-3 h-3 transition-transform duration-150"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div data-section-content>
          <%= if @label_groups == [] do %>
            <p
              class="px-3 py-1 text-[10px] italic"
              style="color: var(--taniwha-sidebar-section)"
            >
              No labels yet
            </p>
          <% else %>
            <.sidebar_filter_item
              label="All"
              value="all"
              active?={Enum.empty?(@label_filter || MapSet.new())}
              count={Enum.reduce(@label_groups, 0, fn {_, c}, acc -> acc + c end)}
            />
            <.sidebar_filter_item
              :for={{label, count} <- @label_groups}
              label={label}
              value={label}
              active?={MapSet.member?(@label_filter || MapSet.new(), label)}
              count={count}
              dot_color={label_dot_color(label)}
            />
            <%!-- Divider above Manage labels --%>
            <div class="mx-3 mt-1 border-t" style="border-color: var(--taniwha-sidebar-border)" />
          <% end %>

          <button
            type="button"
            phx-click="show_label_manager"
            class="flex items-center w-full px-3 h-[27px] text-[10px] text-left cursor-pointer"
            style="color: var(--taniwha-sidebar-section)"
          >
            Manage labels
          </button>
        </div>
      </div>

      <%!-- Divider --%>
      <div class="mx-3 my-1 border-t" style="border-color: var(--taniwha-sidebar-border)" />

      <%!-- Trackers section --%>
      <div data-filter-section="trackers">
        <button
          type="button"
          data-collapse-toggle
          class="flex items-center justify-between w-full px-3 pb-1 pt-0"
          style="color: var(--taniwha-sidebar-section)"
        >
          <span class="text-[10px] font-semibold tracking-[0.08em] uppercase">Trackers</span>
          <svg
            data-collapse-icon
            class="w-3 h-3 transition-transform duration-150"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </button>
        <div data-section-content>
          <%= if @tracker_groups != [] do %>
            <.sidebar_filter_item
              label="All"
              value="all"
              active?={Enum.empty?(@tracker_filter)}
              count={Enum.reduce(@tracker_groups, 0, fn {_, c}, acc -> acc + c end)}
            />
            <.sidebar_filter_item
              :for={{domain, count} <- @tracker_groups}
              label={domain}
              value={domain}
              active?={MapSet.member?(@tracker_filter, domain)}
              count={count}
            />
          <% end %>
        </div>
      </div>
    </nav>

    <script :type={ColocatedHook} name=".SidebarFilter">
      export default {
        _anchors: {},

        mounted() {
          const stored = (() => {
            try { return JSON.parse(localStorage.getItem("taniwha-sidebar-collapse") || "{}") }
            catch { return {} }
          })()

          this.el.querySelectorAll("[data-filter-section]").forEach(section => {
            const name = section.dataset.filterSection
            const content = section.querySelector("[data-section-content]")
            const icon = section.querySelector("[data-collapse-icon]")
            if (stored[name] && content) {
              content.classList.add("hidden")
              if (icon) icon.style.transform = "rotate(-90deg)"
            }
          })

          this._onClick = (e) => {
            // Collapse toggle
            const toggleBtn = e.target.closest("[data-collapse-toggle]")
            if (toggleBtn) {
              const section = toggleBtn.closest("[data-filter-section]")
              if (!section) return
              const content = section.querySelector("[data-section-content]")
              const icon = section.querySelector("[data-collapse-icon]")
              if (!content) return
              const isHidden = content.classList.toggle("hidden")
              if (icon) icon.style.transform = isHidden ? "rotate(-90deg)" : ""
              const name = section.dataset.filterSection
              const stored = (() => {
                try { return JSON.parse(localStorage.getItem("taniwha-sidebar-collapse") || "{}") }
                catch { return {} }
              })()
              stored[name] = isHidden
              localStorage.setItem("taniwha-sidebar-collapse", JSON.stringify(stored))
              return
            }

            // Filter click
            const btn = e.target.closest("[data-filter-value]")
            if (!btn) return
            const sectionEl = btn.closest("[data-filter-section]")
            if (!sectionEl) return
            const section = sectionEl.dataset.filterSection
            const value = btn.dataset.filterValue

            const itemBtns = Array.from(
              sectionEl.querySelectorAll("[data-filter-value]:not([data-filter-value=all])")
            )
            const currentSelected = new Set(
              itemBtns
                .filter(b => b.getAttribute("aria-pressed") === "true")
                .map(b => b.dataset.filterValue)
            )

            let newSelected
            if (value === "all") {
              newSelected = new Set()
              this._anchors[section] = null
            } else if (e.shiftKey && this._anchors[section]) {
              const anchor = this._anchors[section]
              const anchorIdx = itemBtns.findIndex(b => b.dataset.filterValue === anchor)
              const currentIdx = itemBtns.findIndex(b => b.dataset.filterValue === value)
              const [lo, hi] = anchorIdx < currentIdx
                ? [anchorIdx, currentIdx]
                : [currentIdx, anchorIdx]
              newSelected = new Set(itemBtns.slice(lo, hi + 1).map(b => b.dataset.filterValue))
            } else if (e.ctrlKey || e.metaKey) {
              newSelected = new Set(currentSelected)
              if (newSelected.has(value)) newSelected.delete(value)
              else newSelected.add(value)
              this._anchors[section] = value
            } else {
              newSelected = new Set([value])
              this._anchors[section] = value
            }

            this.pushEvent("sidebar_filter", { section, values: [...newSelected] })
          }

          this.el.addEventListener("click", this._onClick)
        },

        destroyed() {
          this.el.removeEventListener("click", this._onClick)
        }
      }
    </script>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :active?, :boolean, required: true
  attr :count, :integer, required: true
  attr :dot_color, :string, default: nil

  defp sidebar_filter_item(assigns) do
    ~H"""
    <button
      type="button"
      data-filter-value={@value}
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

  @spec label_dot_color(String.t()) :: String.t()
  defp label_dot_color(label) do
    {dot, _bg, _text} = Taniwha.LabelStore.auto_assign(label)
    dot
  end

  @spec dl_indicator_label(non_neg_integer(), non_neg_integer()) :: String.t()
  defp dl_indicator_label(rate, 0),
    do: "Download: #{format_speed(rate)}. Right-click to set limit."

  defp dl_indicator_label(rate, limit),
    do:
      "Download: #{format_speed(rate)}, limit: #{Taniwha.ThrottleStore.bytes_to_display(limit)}. Right-click to change."

  @spec ul_indicator_label(non_neg_integer(), non_neg_integer()) :: String.t()
  defp ul_indicator_label(rate, 0),
    do: "Upload: #{format_speed(rate)}. Right-click to set limit."

  defp ul_indicator_label(rate, limit),
    do:
      "Upload: #{format_speed(rate)}, limit: #{Taniwha.ThrottleStore.bytes_to_display(limit)}. Right-click to change."
end
