defmodule TaniwhaWeb.TorrentComponents do
  @moduledoc """
  Reusable LiveView function components for the torrent management UI.

  All components follow WCAG 2.2 AA accessibility guidelines: correct ARIA
  roles, labels, and semantic HTML. Import this module in your LiveViews and
  templates with:

      import TaniwhaWeb.TorrentComponents

  ## Components

  - `progress_bar/1` — animated download/upload progress indicator
  - `status_badge/1` — colour-coded pill showing torrent lifecycle state
  - `speed_display/1` — human-readable transfer speed with directional icon
  - `global_stats_bar/1` — aggregate upload/download rates and torrent counts
  - `torrent_row/1` — full summary row with controls for a single torrent
  """

  use TaniwhaWeb, :html

  alias Taniwha.Torrent

  # ---------------------------------------------------------------------------
  # progress_bar/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a horizontal progress bar with ARIA `progressbar` role.

  ## Attributes

  - `:value` (required) — float between 0.0 and 100.0 representing percentage
  - `:color` — atom determining bar colour: `:blue`, `:green`, `:gray`,
    `:yellow`. Defaults to `:default` (rendered as blue/info).
  - `:id` — optional HTML id attribute
  - `:rest` — any additional HTML attributes passed through to the wrapper

  ## Accessibility

  Sets `role="progressbar"`, `aria-valuenow` (rounded integer), `aria-valuemin`,
  and `aria-valuemax` as required by WCAG.

  ## Examples

      <.progress_bar value={45.5} color={:green} />
      <.progress_bar value={@torrent |> Torrent.progress() |> Kernel.*(100)} color={:blue} id="dl-progress" />
  """
  attr :value, :float, required: true
  attr :color, :atom, default: :default
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
      class="w-full bg-base-300 rounded-full h-2"
      {@rest}
    >
      <div
        class={"h-2 rounded-full transition-all #{progress_color(@color)}"}
        style={"width: #{@value}%"}
      />
    </div>
    """
  end

  @spec progress_color(atom()) :: String.t()
  defp progress_color(:blue), do: "bg-info"
  defp progress_color(:green), do: "bg-success"
  defp progress_color(:gray), do: "bg-neutral"
  defp progress_color(:yellow), do: "bg-warning"
  defp progress_color(_), do: "bg-info"

  # ---------------------------------------------------------------------------
  # status_badge/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a daisyUI badge pill reflecting a torrent's lifecycle status.

  ## Attributes

  - `:status` (required) — one of `:downloading`, `:seeding`, `:stopped`,
    `:paused`, `:checking`, `:unknown`

  ## Examples

      <.status_badge status={Torrent.status(@torrent)} />
  """
  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={"badge #{badge_class(@status)}"}>
      {status_label(@status)}
    </span>
    """
  end

  @spec badge_class(atom()) :: String.t()
  defp badge_class(:downloading), do: "badge-info"
  defp badge_class(:seeding), do: "badge-success"
  defp badge_class(:stopped), do: "badge-neutral"
  defp badge_class(:paused), do: "badge-warning"
  defp badge_class(:checking), do: "badge-primary"
  defp badge_class(_), do: "badge-ghost"

  @spec status_label(atom()) :: String.t()
  defp status_label(:downloading), do: "Downloading"
  defp status_label(:seeding), do: "Seeding"
  defp status_label(:stopped), do: "Stopped"
  defp status_label(:paused), do: "Paused"
  defp status_label(:checking), do: "Checking"
  defp status_label(_), do: "Unknown"

  # ---------------------------------------------------------------------------
  # speed_display/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a human-readable transfer speed with an optional directional icon.

  Automatically scales to B/s, KB/s, MB/s, or GB/s:

  - `< 1 024` bytes → `N B/s`
  - `< 1 048 576` bytes → `N.1 KB/s` (1 decimal place)
  - `< 1 073 741 824` bytes → `N.2 MB/s` (2 decimal places)
  - Otherwise → `N.2 GB/s` (2 decimal places)

  ## Attributes

  - `:bytes_per_second` (required) — non-negative integer
  - `:direction` — `:up` renders `hero-arrow-up-micro`; `:down` renders
    `hero-arrow-down-micro`; `nil` renders no icon

  ## Examples

      <.speed_display bytes_per_second={@torrent.download_rate} direction={:down} />
      <.speed_display bytes_per_second={@torrent.upload_rate} direction={:up} />
  """
  attr :bytes_per_second, :integer, required: true
  attr :direction, :atom, default: nil

  def speed_display(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-0.5 tabular-nums text-sm">
      <.icon :if={@direction == :up} name="hero-arrow-up-micro" class="size-3 shrink-0" />
      <.icon :if={@direction == :down} name="hero-arrow-down-micro" class="size-3 shrink-0" />
      {format_speed(@bytes_per_second)}
    </span>
    """
  end

  @doc false
  @spec format_speed(non_neg_integer()) :: String.t()
  defp format_speed(bytes) when bytes < 1_024 do
    "#{bytes} B/s"
  end

  defp format_speed(bytes) when bytes < 1_048_576 do
    :erlang.float_to_binary(bytes / 1_024, decimals: 1) <> " KB/s"
  end

  defp format_speed(bytes) when bytes < 1_073_741_824 do
    :erlang.float_to_binary(bytes / 1_048_576, decimals: 2) <> " MB/s"
  end

  defp format_speed(bytes) do
    :erlang.float_to_binary(bytes / 1_073_741_824, decimals: 2) <> " GB/s"
  end

  # ---------------------------------------------------------------------------
  # global_stats_bar/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the aggregate transfer statistics bar shown in the app layout navbar.

  Displays total upload rate, download rate, and active/total torrent counts.
  Accepts default-zero assigns so LiveViews that haven't yet subscribed to
  PubSub still render correctly.

  ## Attributes

  - `:upload_rate` — integer bytes/s, default 0
  - `:download_rate` — integer bytes/s, default 0
  - `:active_count` — integer, default 0
  - `:total_count` — integer, default 0

  ## Accessibility

  Sets `role="status"` and `aria-label="Global transfer statistics"` so screen
  readers announce updates when values change via PubSub.

  ## Examples

      <.global_stats_bar
        upload_rate={@global_upload_rate}
        download_rate={@global_download_rate}
        active_count={@active_count}
        total_count={@total_count}
      />
  """
  attr :upload_rate, :integer, default: 0
  attr :download_rate, :integer, default: 0
  attr :active_count, :integer, default: 0
  attr :total_count, :integer, default: 0

  def global_stats_bar(assigns) do
    ~H"""
    <div
      role="status"
      aria-label="Global transfer statistics"
      class="hidden sm:flex items-center gap-3 text-xs text-base-content/70"
    >
      <.speed_display bytes_per_second={@upload_rate} direction={:up} />
      <.speed_display bytes_per_second={@download_rate} direction={:down} />
      <span class="tabular-nums">
        {@active_count}/{@total_count}
      </span>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # torrent_row/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a full summary row for a single torrent.

  Displays: name (truncated with full name as tooltip), progress bar, download
  and upload speeds, ratio, status badge, and start/stop/remove action buttons.

  The row is rendered as an `<article>` with `aria-label` set to the torrent
  name for screen-reader navigation.

  ## Attributes

  - `:torrent` (required) — a `Taniwha.Torrent` struct
  - `:on_start` — event name or JS command for the start button
  - `:on_stop` — event name or JS command for the stop button
  - `:on_remove` — event name or JS command for the remove button

  ## Examples

      <.torrent_row
        torrent={torrent}
        on_start="start_torrent"
        on_stop="stop_torrent"
        on_remove="remove_torrent"
      />
  """
  attr :torrent, :map, required: true
  attr :on_start, :any, default: nil
  attr :on_stop, :any, default: nil
  attr :on_remove, :any, default: nil

  def torrent_row(assigns) do
    assigns =
      assigns
      |> assign(:progress, Torrent.progress(assigns.torrent) * 100)
      |> assign(:status, Torrent.status(assigns.torrent))

    ~H"""
    <article
      aria-label={@torrent.name}
      class="grid grid-cols-[1fr_auto] gap-2 p-3 rounded-lg bg-base-200 hover:bg-base-300 transition-colors"
    >
      <%!-- Top row: name + status badge --%>
      <div class="flex items-center gap-2 min-w-0">
        <span class="truncate font-medium" title={@torrent.name}>
          {@torrent.name}
        </span>
        <.status_badge status={@status} />
      </div>

      <%!-- Action buttons --%>
      <div class="flex items-center gap-1">
        <button
          :if={@status in [:stopped, :paused]}
          phx-click={@on_start}
          phx-value-hash={@torrent.hash}
          aria-label={"Start #{@torrent.name}"}
          class="btn btn-ghost btn-xs"
        >
          <.icon name="hero-play-micro" class="size-4" />
        </button>

        <button
          :if={@status in [:downloading, :seeding, :checking]}
          phx-click={@on_stop}
          phx-value-hash={@torrent.hash}
          aria-label={"Stop #{@torrent.name}"}
          class="btn btn-ghost btn-xs"
        >
          <.icon name="hero-stop-micro" class="size-4" />
        </button>

        <button
          phx-click={@on_remove}
          phx-value-hash={@torrent.hash}
          aria-label={"Remove #{@torrent.name}"}
          class="btn btn-ghost btn-xs text-error"
        >
          <.icon name="hero-trash-micro" class="size-4" />
        </button>
      </div>

      <%!-- Progress bar (full width, second row) --%>
      <div class="col-span-2">
        <.progress_bar value={@progress} color={status_to_color(@status)} />
      </div>

      <%!-- Speeds + ratio (third row) --%>
      <div class="col-span-2 flex items-center gap-4 text-xs text-base-content/60">
        <.speed_display bytes_per_second={@torrent.download_rate} direction={:down} />
        <.speed_display bytes_per_second={@torrent.upload_rate} direction={:up} />
        <span class="tabular-nums">
          ratio: {Float.round(@torrent.ratio * 1.0, 2)}
        </span>
      </div>
    </article>
    """
  end

  @spec status_to_color(atom()) :: atom()
  defp status_to_color(:downloading), do: :blue
  defp status_to_color(:seeding), do: :green
  defp status_to_color(:paused), do: :yellow
  defp status_to_color(:checking), do: :yellow
  defp status_to_color(_), do: :gray
end
