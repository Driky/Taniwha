defmodule TaniwhaWeb.TorrentComponents.DetailComponents do
  @moduledoc """
  Detail panel components: the slide-up panel container and its four content
  tabs (General, Files, Peers, Trackers).
  """

  use TaniwhaWeb, :html

  import TaniwhaWeb.FormatHelpers,
    only: [format_bytes: 1, format_eta: 1, format_ratio: 1, format_speed: 1]

  import TaniwhaWeb.TorrentComponents.StatusComponents, only: [progress_bar: 1, speed_display: 1]

  alias Phoenix.LiveView.AsyncResult
  alias Taniwha.{Peer, Torrent, Tracker, TorrentFile}

  # ---------------------------------------------------------------------------
  # detail_panel/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the slide-up detail panel anchored at the bottom of the main column.

  The panel is hidden (`max-h-0`) when `torrent` is `nil` and visible
  (`max-h-80`) when a torrent is selected. Uses a CSS `max-height` transition
  for a smooth open/close animation.

  ## Attributes

  - `:torrent` — the selected `Torrent.t()` or `nil`
  - `:active_tab` — active tab atom: `:general`, `:files`, `:peers`, `:trackers`
  - `:detail_files` — `AsyncResult` for file list
  - `:detail_peers` — `AsyncResult` for peer list
  - `:detail_trackers` — `AsyncResult` for tracker list
  """
  attr :torrent, :map, default: nil
  attr :active_tab, :atom, default: :general
  attr :detail_files, :any, required: true
  attr :detail_peers, :any, required: true
  attr :detail_trackers, :any, required: true

  def detail_panel(assigns) do
    ~H"""
    <div
      id="detail-panel"
      role="region"
      aria-label="Torrent details"
      class={[
        "border-t overflow-hidden transition-[max-height] duration-200 ease-out shrink-0",
        "bg-white dark:bg-[#111827]",
        if(@torrent, do: "max-h-[220px]", else: "max-h-0")
      ]}
      style="border-color: var(--taniwha-row-border)"
    >
      <div :if={@torrent} class="flex flex-col h-[220px]">
        <%!-- Tab bar --%>
        <div
          role="tablist"
          class="flex items-center border-b shrink-0 bg-[#f9fafb] dark:bg-[#0d1015] px-3"
          style="height: 34px; border-color: #e5e7eb"
        >
          <.panel_tab label="General" tab={:general} active_tab={@active_tab} />
          <.panel_tab label="Files" tab={:files} active_tab={@active_tab} />
          <.panel_tab label="Peers" tab={:peers} active_tab={@active_tab} />
          <.panel_tab label="Trackers" tab={:trackers} active_tab={@active_tab} />
          <div class="flex-1" />
          <span
            class="text-[11px] font-medium text-[#374151] dark:text-[#d1d5db] mr-3 truncate max-w-[200px]"
            title={@torrent.name}
          >
            {@torrent.name}
          </span>
          <button
            type="button"
            phx-click="close_panel"
            aria-label="Close detail panel"
            class="w-[22px] h-[22px] flex items-center justify-center rounded-[4px] text-[#9ca3af] dark:text-[#6b7280] hover:bg-[#f3f4f6] dark:hover:bg-[#1f2937] shrink-0"
          >
            <.icon name="hero-x-mark" class="size-3" />
          </button>
        </div>

        <%!-- Tab content --%>
        <div
          id={"panel-tabpanel-#{@active_tab}"}
          role="tabpanel"
          aria-labelledby={"panel-tab-#{@active_tab}"}
          class="flex-1 overflow-y-auto px-4 py-3"
        >
          <.general_tab :if={@active_tab == :general} torrent={@torrent} />
          <.files_tab
            :if={@active_tab == :files}
            torrent={@torrent}
            detail_files={@detail_files}
          />
          <.peers_tab :if={@active_tab == :peers} detail_peers={@detail_peers} />
          <.trackers_tab :if={@active_tab == :trackers} detail_trackers={@detail_trackers} />
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tab, :atom, required: true
  attr :active_tab, :atom, required: true

  defp panel_tab(assigns) do
    ~H"""
    <button
      id={"panel-tab-#{@tab}"}
      type="button"
      role="tab"
      aria-selected={to_string(@tab == @active_tab)}
      phx-click="switch_tab"
      phx-value-tab={to_string(@tab)}
      class={[
        "h-full px-[14px] text-[11px] border-b-2 transition-colors mb-[-1px]",
        if(@tab == @active_tab,
          do: "border-[#3b82f6] text-[#2563eb] dark:text-[#60a5fa] font-medium",
          else: "border-transparent text-[#6b7280] hover:text-[#374151] dark:hover:text-[#d1d5db]"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # general_tab/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the General tab of the detail panel: a key-value grid of torrent
  metadata fields.

  ## Attributes

  - `:torrent` (required) — the selected `Torrent.t()`
  """
  attr :torrent, Torrent, required: true

  def general_tab(assigns) do
    assigns =
      assigns
      |> assign(:progress_pct, round(Torrent.progress(assigns.torrent) * 100))
      |> assign(:eta, compute_eta(assigns.torrent))

    ~H"""
    <div class="grid grid-cols-3 gap-y-2 gap-x-6 text-[11px]">
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Save path</div>
        <div class="text-[#374151] dark:text-[#d1d5db] truncate" title={@torrent.base_path || "—"}>
          {@torrent.base_path || "—"}
        </div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Total size</div>
        <div class="text-[#374151] dark:text-[#d1d5db]">{format_bytes(@torrent.size)}</div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Downloaded</div>
        <div>
          <span class="text-[#374151] dark:text-[#d1d5db]">
            {format_bytes(@torrent.completed_bytes)}
          </span>
          <span class="text-[#9ca3af] dark:text-[#6b7280] ml-[2px]">({@progress_pct}%)</span>
        </div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Download speed</div>
        <div class="text-[#2563eb] dark:text-[#60a5fa] font-medium">
          {format_speed(@torrent.download_rate)}
        </div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Upload speed</div>
        <div class="text-[#16a34a] dark:text-[#4ade80] font-medium">
          {format_speed(@torrent.upload_rate)}
        </div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">ETA</div>
        <div class="text-[#374151] dark:text-[#d1d5db]">{format_eta(@eta)}</div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Seeds</div>
        <div class="text-[#374151] dark:text-[#d1d5db]">—</div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Peers</div>
        <div class="text-[#374151] dark:text-[#d1d5db]">{@torrent.peers_connected}</div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Ratio</div>
        <div class="text-[#374151] dark:text-[#d1d5db]">{format_ratio(@torrent.ratio)}</div>
      </div>
      <div class="col-span-3">
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Hash</div>
        <div class="font-mono text-[10px] text-[#374151] dark:text-[#9ca3af] bg-[#f9fafb] dark:bg-[#1f2937] border border-[#e5e7eb] dark:border-[#374151] rounded px-[6px] py-[3px]">
          {@torrent.hash}
        </div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Date added</div>
        <div class="text-[#374151] dark:text-[#d1d5db]">{format_datetime(@torrent.started_at)}</div>
      </div>
      <div>
        <div class="text-[#9ca3af] dark:text-[#4b5563] text-[10px] mb-[2px]">Completed</div>
        <%= if @torrent.finished_at do %>
          <div class="text-[#374151] dark:text-[#d1d5db]">
            {format_datetime(@torrent.finished_at)}
          </div>
        <% else %>
          <div class="text-[#9ca3af] dark:text-[#6b7280] italic">In progress…</div>
        <% end %>
      </div>
    </div>
    """
  end

  @spec compute_eta(Torrent.t()) :: non_neg_integer() | nil
  defp compute_eta(%Torrent{complete: true}), do: 0

  defp compute_eta(%Torrent{download_rate: rate, size: size, completed_bytes: done})
       when rate > 0 do
    div(size - done, rate)
  end

  defp compute_eta(_), do: nil

  @spec format_datetime(DateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: "—"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp loading_skeleton(assigns) do
    ~H"""
    <div class="space-y-[6px]">
      <div :for={_ <- 1..4} class="h-[28px] rounded animate-pulse bg-[#f3f4f6] dark:bg-[#1f2937]" />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # files_tab/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the Files tab: an async-loaded table of files within a torrent,
  with per-file priority selects and progress bars.

  ## Attributes

  - `:torrent` (required) — the selected `Torrent.t()` (for the hash)
  - `:detail_files` (required) — `AsyncResult` holding `[TorrentFile.t()]`
  """
  attr :torrent, Torrent, required: true
  attr :detail_files, AsyncResult, required: true

  def files_tab(assigns) do
    ~H"""
    <.async_result :let={files} assign={@detail_files}>
      <:loading><.loading_skeleton /></:loading>
      <:failed :let={_reason}>
        <p class="text-[11px] text-[#ef4444]">Failed to load files</p>
      </:failed>
      <p :if={files == []} class="text-[11px]" style="color: var(--taniwha-col-header)">
        No files
      </p>
      <table :if={files != []} class="w-full border-collapse text-[11px]">
        <thead>
          <tr
            class="border-b text-[#6b7280]"
            style="border-color: var(--taniwha-row-border)"
          >
            <th scope="col" class="text-left pb-1 pr-2" style="width: 40%">Name</th>
            <th scope="col" class="text-right pb-1 pr-2" style="width: 80px">Size</th>
            <th scope="col" class="text-left pb-1 pr-2" style="width: 120px">Progress</th>
            <th scope="col" class="text-left pb-1" style="width: 90px">Priority</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={{file, index} <- Enum.with_index(files)}
            class="border-b"
            style="height: 28px; border-color: var(--taniwha-row-border)"
          >
            <td class="pr-2 overflow-hidden">
              <span class="block truncate" title={file.path}>{file_name(file.path)}</span>
            </td>
            <td class="pr-2 text-right tabular-nums" style="color: var(--taniwha-cell-num)">
              {format_bytes(file.size)}
            </td>
            <td class="pr-2">
              <div class="flex items-center gap-[4px]">
                <span
                  class="shrink-0 w-[28px] text-right tabular-nums"
                  style="color: var(--taniwha-cell-pct)"
                >
                  {round(TorrentFile.progress(file) * 100)}%
                </span>
                <div class="flex-1">
                  <.progress_bar
                    value={TorrentFile.progress(file) * 100}
                    color={:downloading}
                  />
                </div>
              </div>
            </td>
            <td>
              <select
                phx-change="set_file_priority"
                phx-value-hash={@torrent.hash}
                phx-value-index={index}
                name="priority"
                class="text-[10px] border rounded px-1 py-0"
                style="border-color: var(--taniwha-row-border)"
              >
                <option value="0" selected={file.priority == 0}>Skip</option>
                <option value="1" selected={file.priority == 1}>Normal</option>
                <option value="2" selected={file.priority == 2}>High</option>
              </select>
            </td>
          </tr>
        </tbody>
      </table>
    </.async_result>
    """
  end

  @spec file_name(String.t() | nil) :: String.t()
  defp file_name(nil), do: "—"
  defp file_name(path), do: Path.basename(path)

  # ---------------------------------------------------------------------------
  # peers_tab/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the Peers tab: an async-loaded table of connected peers.

  ## Attributes

  - `:detail_peers` (required) — `AsyncResult` holding `[Peer.t()]`
  """
  attr :detail_peers, AsyncResult, required: true

  def peers_tab(assigns) do
    ~H"""
    <.async_result :let={peers} assign={@detail_peers}>
      <:loading><.loading_skeleton /></:loading>
      <:failed :let={_reason}>
        <p class="text-[11px] text-[#ef4444]">Failed to load peers</p>
      </:failed>
      <p :if={peers == []} class="text-[11px]" style="color: var(--taniwha-col-header)">
        No peers connected
      </p>
      <table :if={peers != []} class="w-full border-collapse text-[11px]">
        <thead>
          <tr
            class="border-b text-[#6b7280]"
            style="border-color: var(--taniwha-row-border)"
          >
            <th scope="col" class="text-left pb-1 pr-2">IP:Port</th>
            <th scope="col" class="text-left pb-1 pr-2">Client</th>
            <th scope="col" class="text-right pb-1 pr-2">Down</th>
            <th scope="col" class="text-right pb-1 pr-2">Up</th>
            <th scope="col" class="text-right pb-1">Progress</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={peer <- peers}
            class="border-b"
            style="height: 28px; border-color: var(--taniwha-row-border)"
          >
            <td class="pr-2">
              <span class="font-mono" style="color: var(--taniwha-cell-name)">
                {Peer.address_port(peer)}
              </span>
            </td>
            <td class="pr-2 truncate" style="color: var(--taniwha-cell-name)">
              {peer.client_version}
            </td>
            <td class="pr-2 text-right">
              <.speed_display bytes_per_second={peer.down_rate} direction={:down} />
            </td>
            <td class="pr-2 text-right">
              <.speed_display bytes_per_second={peer.up_rate} direction={:up} />
            </td>
            <td class="text-right tabular-nums" style="color: var(--taniwha-cell-pct)">
              {round(peer.completed_percent)}%
            </td>
          </tr>
        </tbody>
      </table>
    </.async_result>
    """
  end

  # ---------------------------------------------------------------------------
  # trackers_tab/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders the Trackers tab: an async-loaded table of trackers with
  colour-coded status indicators.

  ## Attributes

  - `:detail_trackers` (required) — `AsyncResult` holding `[Tracker.t()]`
  """
  attr :detail_trackers, AsyncResult, required: true

  def trackers_tab(assigns) do
    ~H"""
    <.async_result :let={trackers} assign={@detail_trackers}>
      <:loading><.loading_skeleton /></:loading>
      <:failed :let={_reason}>
        <p class="text-[11px] text-[#ef4444]">Failed to load trackers</p>
      </:failed>
      <p :if={trackers == []} class="text-[11px]" style="color: var(--taniwha-col-header)">
        No trackers
      </p>
      <table :if={trackers != []} class="w-full border-collapse text-[11px]">
        <thead>
          <tr
            class="border-b text-[#6b7280]"
            style="border-color: var(--taniwha-row-border)"
          >
            <th scope="col" class="text-left pb-1 pr-2">URL</th>
            <th scope="col" class="text-left pb-1 pr-2" style="width: 70px">Status</th>
            <th scope="col" class="text-right pb-1 pr-2" style="width: 60px">Seeds</th>
            <th scope="col" class="text-right pb-1" style="width: 60px">Peers</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={tracker <- trackers}
            class="border-b"
            style="height: 28px; border-color: var(--taniwha-row-border)"
          >
            <td class="pr-2 overflow-hidden">
              <span class="block truncate" title={tracker.url}>{tracker_host(tracker.url)}</span>
            </td>
            <td class="pr-2">
              <span class={tracker_status_class(Tracker.status(tracker))}>
                {tracker_status_label(Tracker.status(tracker))}
              </span>
            </td>
            <td class="pr-2 text-right tabular-nums" style="color: var(--taniwha-cell-num)">
              {tracker.scrape_complete}
            </td>
            <td class="text-right tabular-nums" style="color: var(--taniwha-cell-num)">
              {tracker.scrape_incomplete}
            </td>
          </tr>
        </tbody>
      </table>
    </.async_result>
    """
  end

  @spec tracker_host(String.t()) :: String.t()
  defp tracker_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> url
    end
  end

  @spec tracker_status_class(:enabled | :disabled) :: String.t()
  defp tracker_status_class(:enabled), do: "text-green-600 dark:text-green-400"
  defp tracker_status_class(:disabled), do: "text-gray-400 dark:text-gray-500"

  @spec tracker_status_label(:enabled | :disabled) :: String.t()
  defp tracker_status_label(:enabled), do: "Active"
  defp tracker_status_label(:disabled), do: "Disabled"
end
