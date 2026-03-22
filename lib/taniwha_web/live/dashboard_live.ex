defmodule TaniwhaWeb.DashboardLive do
  @moduledoc """
  Main torrent dashboard LiveView.

  Displays all torrents from the ETS state cache with real-time PubSub updates.
  Supports search/filter/sort, per-torrent lifecycle actions, and bulk selection.
  """

  use TaniwhaWeb, :live_view

  alias Taniwha.{State.Store, Torrent}

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    torrents = Store.get_all_torrents()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:list")
    end

    socket =
      socket
      |> assign(:torrents, torrents)
      |> assign(:search, "")
      |> assign(:sort_by, :name)
      |> assign(:sort_dir, :asc)
      |> assign(:filter, :all)
      |> assign(:selected_hashes, MapSet.new())
      |> assign(:page_title, "Torrents")
      |> assign_global_stats(torrents)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:torrent_diffs, diffs}, socket) do
    torrents = apply_diffs(socket.assigns.torrents, diffs)

    socket =
      socket
      |> assign(:torrents, torrents)
      |> assign_global_stats(torrents)

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, assign(socket, :search, v)}
  end

  def handle_event("filter", %{"value" => v}, socket) do
    {:noreply, assign(socket, :filter, parse_filter(v))}
  end

  def handle_event("sort", %{"by" => col}, socket) do
    col_atom = parse_sort_column(col)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == col_atom do
        {col_atom, toggle_dir(socket.assigns.sort_dir)}
      else
        {col_atom, :asc}
      end

    {:noreply, assign(socket, sort_by: sort_by, sort_dir: sort_dir)}
  end

  def handle_event("start_torrent", %{"hash" => hash}, socket) do
    @commands.start(hash)
    {:noreply, socket}
  end

  def handle_event("stop_torrent", %{"hash" => hash}, socket) do
    @commands.stop(hash)
    {:noreply, socket}
  end

  def handle_event("remove_torrent", %{"hash" => hash}, socket) do
    @commands.erase(hash)

    torrents = Enum.reject(socket.assigns.torrents, &(&1.hash == hash))
    selected = MapSet.delete(socket.assigns.selected_hashes, hash)

    socket =
      socket
      |> assign(:torrents, torrents)
      |> assign(:selected_hashes, selected)
      |> assign_global_stats(torrents)

    {:noreply, socket}
  end

  def handle_event("toggle_select", %{"hash" => hash}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_hashes, hash) do
        MapSet.delete(socket.assigns.selected_hashes, hash)
      else
        MapSet.put(socket.assigns.selected_hashes, hash)
      end

    {:noreply, assign(socket, :selected_hashes, selected)}
  end

  def handle_event("select_all", _params, socket) do
    %{torrents: torrents, search: search, filter: filter, sort_by: sort_by, sort_dir: sort_dir} =
      socket.assigns

    visible = visible_torrents(torrents, search, filter, sort_by, sort_dir)
    selected = visible |> Enum.map(& &1.hash) |> MapSet.new()
    {:noreply, assign(socket, :selected_hashes, selected)}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_hashes, MapSet.new())}
  end

  def handle_event("bulk_start", _params, socket) do
    Enum.each(socket.assigns.selected_hashes, &@commands.start/1)
    {:noreply, socket}
  end

  def handle_event("bulk_stop", _params, socket) do
    Enum.each(socket.assigns.selected_hashes, &@commands.stop/1)
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Public helpers (called from template)
  # ---------------------------------------------------------------------------

  @doc false
  @spec visible_torrents([Torrent.t()], String.t(), atom(), atom(), atom()) :: [Torrent.t()]
  def visible_torrents(torrents, search, filter, sort_by, sort_dir) do
    torrents
    |> filter_by_status(filter)
    |> filter_by_search(search)
    |> sort_torrents(sort_by, sort_dir)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec apply_diffs([Torrent.t()], list()) :: [Torrent.t()]
  defp apply_diffs(torrents, diffs) do
    torrent_map = Map.new(torrents, &{&1.hash, &1})

    updated =
      Enum.reduce(diffs, torrent_map, fn
        {:added, torrent}, acc -> Map.put(acc, torrent.hash, torrent)
        {:updated, torrent}, acc -> Map.put(acc, torrent.hash, torrent)
        {:removed, hash}, acc -> Map.delete(acc, hash)
      end)

    Map.values(updated)
  end

  @spec assign_global_stats(Phoenix.LiveView.Socket.t(), [Torrent.t()]) ::
          Phoenix.LiveView.Socket.t()
  defp assign_global_stats(socket, torrents) do
    {active, upload_rate, download_rate, total} =
      Enum.reduce(torrents, {0, 0, 0, 0}, fn t, {ac, up, down, tot} ->
        inc = if Torrent.status(t) in [:downloading, :seeding, :checking], do: 1, else: 0
        {ac + inc, up + t.upload_rate, down + t.download_rate, tot + 1}
      end)

    socket
    |> assign(:global_upload_rate, upload_rate)
    |> assign(:global_download_rate, download_rate)
    |> assign(:active_count, active)
    |> assign(:total_count, total)
  end

  @spec filter_by_status([Torrent.t()], atom()) :: [Torrent.t()]
  defp filter_by_status(torrents, :all), do: torrents

  defp filter_by_status(torrents, status) do
    Enum.filter(torrents, fn t -> Torrent.status(t) == status end)
  end

  @spec filter_by_search([Torrent.t()], String.t()) :: [Torrent.t()]
  defp filter_by_search(torrents, ""), do: torrents

  defp filter_by_search(torrents, query) do
    q = String.downcase(query)
    Enum.filter(torrents, fn t -> String.contains?(String.downcase(t.name), q) end)
  end

  @sort_columns [:name, :size, :progress, :speed, :ratio, :status]

  @spec sort_torrents([Torrent.t()], atom(), atom()) :: [Torrent.t()]
  defp sort_torrents(torrents, col, dir) when col in @sort_columns do
    Enum.sort_by(torrents, sort_key(col), dir)
  end

  defp sort_torrents(torrents, _col, _dir), do: torrents

  @spec sort_key(atom()) :: (Torrent.t() -> term())
  defp sort_key(:name), do: & &1.name
  defp sort_key(:size), do: & &1.size
  defp sort_key(:progress), do: &Torrent.progress/1
  defp sort_key(:speed), do: & &1.download_rate
  defp sort_key(:ratio), do: & &1.ratio
  defp sort_key(:status), do: &Torrent.status/1

  @spec parse_filter(String.t()) :: atom()
  defp parse_filter("all"), do: :all
  defp parse_filter("downloading"), do: :downloading
  defp parse_filter("seeding"), do: :seeding
  defp parse_filter("stopped"), do: :stopped
  defp parse_filter(_), do: :all

  @spec parse_sort_column(String.t()) :: atom()
  defp parse_sort_column("name"), do: :name
  defp parse_sort_column("size"), do: :size
  defp parse_sort_column("progress"), do: :progress
  defp parse_sort_column("speed"), do: :speed
  defp parse_sort_column("ratio"), do: :ratio
  defp parse_sort_column("status"), do: :status
  defp parse_sort_column(_), do: :name

  @spec toggle_dir(:asc | :desc) :: :desc | :asc
  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc
end
