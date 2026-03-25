defmodule TaniwhaWeb.TorrentComponents.StatusComponents do
  @moduledoc """
  Primitive status indicator components: progress bar, status badge, speed display.

  These are leaf components used throughout the Taniwha UI. Import this module
  wherever you need to render torrent status or speed values.
  """

  use TaniwhaWeb, :html

  import TaniwhaWeb.FormatHelpers, only: [format_speed: 1]

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
end
