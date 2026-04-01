defmodule TaniwhaWeb.DashboardLive do
  @moduledoc """
  Main torrent dashboard LiveView.

  Displays all torrents from the ETS state cache with real-time PubSub updates.
  Supports search/filter/sort, per-torrent lifecycle actions, and bulk selection.
  """

  use TaniwhaWeb, :live_view

  use TaniwhaWeb.TorrentComponents
  import TaniwhaWeb.FormatHelpers, only: [format_add_error: 1]

  alias Taniwha.{State.Store, Torrent}
  alias Phoenix.LiveView.AsyncResult

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    torrents = Store.get_all_torrents()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:list")
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "system:status")
    end

    socket =
      socket
      |> allow_upload(:torrent_file,
        accept: ~w[application/x-bittorrent .torrent],
        max_entries: 1,
        max_file_size: 10_000_000
      )
      |> assign(:torrents, torrents)
      |> assign(:search, "")
      |> assign(:sort_by, :name)
      |> assign(:sort_dir, :asc)
      |> assign(:filter, :all)
      |> assign(:tracker_filter, :all)
      |> assign(:tracker_groups, [])
      |> assign(:label_filter, :all)
      |> assign(:label_groups, label_groups(torrents))
      |> assign(:show_label_manager, false)
      |> assign(:selected_hashes, MapSet.new())
      |> assign(:selected_hash, nil)
      |> assign(:active_tab, :general)
      |> assign(:detail_files, %AsyncResult{})
      |> assign(:detail_peers, %AsyncResult{})
      |> assign(:detail_trackers, %AsyncResult{})
      |> assign(:page_title, "Torrents")
      |> assign(:confirm_action, nil)
      |> assign(:show_add_modal, false)
      |> assign(:connection_status, :connected)
      |> assign(:downloads_dir_configured?, Application.get_env(:taniwha, :downloads_dir) != nil)
      |> assign_global_stats(torrents)
      |> assign(:status_counts, status_counts(torrents))

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:torrent_updated, torrent}, socket) do
    socket =
      update(socket, :torrents, fn ts ->
        Enum.map(ts, fn t -> if t.hash == torrent.hash, do: torrent, else: t end)
      end)

    {:noreply, assign(socket, :label_groups, label_groups(socket.assigns.torrents))}
  end

  def handle_info({:torrent_diffs, diffs}, socket) do
    torrents = apply_diffs(socket.assigns.torrents, diffs)
    removed_hashes = for {:removed, hash} <- diffs, into: MapSet.new(), do: hash

    socket =
      socket
      |> assign(:torrents, torrents)
      |> assign_global_stats(torrents)
      |> assign(:status_counts, status_counts(torrents))
      |> assign(:label_groups, label_groups(torrents))
      |> maybe_close_detail_panel(removed_hashes)

    {:noreply, socket}
  end

  def handle_info({:connection_status, :disconnected}, socket) do
    {:noreply, assign(socket, :connection_status, :disconnected)}
  end

  def handle_info({:connection_status, :connected}, socket) do
    socket =
      if socket.assigns.connection_status == :disconnected do
        put_flash(socket, :info, "Reconnected")
      else
        socket
      end

    {:noreply, assign(socket, :connection_status, :connected)}
  end

  def handle_info({:add_torrent_success}, socket) do
    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> put_flash(:success, "Torrent added")}
  end

  def handle_info({:hide_label_manager}, socket) do
    {:noreply, assign(socket, :show_label_manager, false)}
  end

  def handle_info({:label_created, name}, socket) do
    label_groups = socket.assigns.label_groups

    label_groups =
      if Enum.any?(label_groups, fn {n, _} -> n == name end) do
        label_groups
      else
        Enum.sort_by([{name, 0} | label_groups], &elem(&1, 0))
      end

    {:noreply, assign(socket, :label_groups, label_groups)}
  end

  def handle_info({:label_deleted, label}, socket) do
    label_filter =
      if socket.assigns.label_filter == label, do: :all, else: socket.assigns.label_filter

    label_groups = Enum.reject(socket.assigns.label_groups, fn {n, _} -> n == label end)

    {:noreply,
     socket |> assign(:label_filter, label_filter) |> assign(:label_groups, label_groups)}
  end

  def handle_info({:label_renamed, old_name, new_name}, socket) do
    label_filter =
      if socket.assigns.label_filter == old_name, do: :all, else: socket.assigns.label_filter

    label_groups =
      socket.assigns.label_groups
      |> Enum.map(fn
        {^old_name, count} -> {new_name, count}
        other -> other
      end)
      |> Enum.sort_by(&elem(&1, 0))

    {:noreply,
     socket |> assign(:label_filter, label_filter) |> assign(:label_groups, label_groups)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("context_menu_action", %{"action" => "start", "hashes" => hashes}, socket) do
    socket =
      Enum.reduce(hashes, socket, fn hash, acc ->
        case @commands.start(hash) do
          :ok -> acc
          {:error, reason} -> put_flash(acc, :error, "Failed to start: #{inspect(reason)}")
        end
      end)

    {:noreply, socket}
  end

  def handle_event("context_menu_action", %{"action" => "stop", "hashes" => hashes}, socket) do
    socket =
      Enum.reduce(hashes, socket, fn hash, acc ->
        case @commands.stop(hash) do
          :ok -> acc
          {:error, reason} -> put_flash(acc, :error, "Failed to stop: #{inspect(reason)}")
        end
      end)

    {:noreply, socket}
  end

  def handle_event("context_menu_action", %{"action" => "pause", "hashes" => hashes}, socket) do
    socket =
      Enum.reduce(hashes, socket, fn hash, acc ->
        case @commands.pause(hash) do
          :ok -> acc
          {:error, reason} -> put_flash(acc, :error, "Failed to pause: #{inspect(reason)}")
        end
      end)

    {:noreply, socket}
  end

  def handle_event("context_menu_action", %{"action" => "erase", "hashes" => [hash]}, socket) do
    {:noreply, assign(socket, :confirm_action, {:erase, hash})}
  end

  def handle_event("context_menu_action", %{"action" => "erase", "hashes" => hashes}, socket) do
    {:noreply, assign(socket, :confirm_action, {:bulk_erase, hashes})}
  end

  def handle_event(
        "context_menu_action",
        %{"action" => "erase_with_data", "hashes" => [hash]},
        socket
      ) do
    base_path = find_base_path(socket.assigns.torrents, hash)
    {:noreply, assign(socket, :confirm_action, {:erase_with_data, hash, base_path})}
  end

  def handle_event(
        "context_menu_action",
        %{"action" => "erase_with_data", "hashes" => hashes},
        socket
      ) do
    paths = Enum.map(hashes, &find_base_path(socket.assigns.torrents, &1))
    {:noreply, assign(socket, :confirm_action, {:bulk_erase_with_data, hashes, paths})}
  end

  def handle_event("context_menu_action", %{"action" => "set_label_prompt"}, socket) do
    {:noreply, assign(socket, :show_label_manager, true)}
  end

  def handle_event(
        "context_menu_action",
        %{"action" => "remove_label", "hashes" => hashes},
        socket
      ) do
    Enum.each(hashes, &@commands.remove_label/1)
    {:noreply, socket}
  end

  def handle_event("context_menu_action", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("search", %{"value" => v}, socket) do
    {:noreply, assign(socket, :search, v)}
  end

  def handle_event("filter", %{"filter" => v}, socket) do
    {:noreply, assign(socket, :filter, parse_filter(v))}
  end

  def handle_event("filter_tracker", %{"filter" => domain}, socket) do
    {:noreply, assign(socket, :tracker_filter, parse_tracker_filter(domain))}
  end

  def handle_event("filter_label", %{"filter" => v}, socket) do
    {:noreply, assign(socket, :label_filter, parse_label_filter(v))}
  end

  def handle_event("show_label_manager", _params, socket) do
    {:noreply, assign(socket, :show_label_manager, true)}
  end

  def handle_event("hide_label_manager", _params, socket) do
    {:noreply, assign(socket, :show_label_manager, false)}
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
    case @commands.start(hash) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end

  def handle_event("stop_torrent", %{"hash" => hash}, socket) do
    case @commands.stop(hash) do
      :ok ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_torrent", %{"hash" => hash}, socket) do
    {:noreply, assign(socket, :confirm_action, {:erase, hash})}
  end

  def handle_event("bulk_remove", _params, socket) do
    hashes = MapSet.to_list(socket.assigns.selected_hashes)
    {:noreply, assign(socket, :confirm_action, {:bulk_erase, hashes})}
  end

  def handle_event("bulk_remove_with_data", _params, socket) do
    hashes = MapSet.to_list(socket.assigns.selected_hashes)
    paths = Enum.map(hashes, &find_base_path(socket.assigns.torrents, &1))
    {:noreply, assign(socket, :confirm_action, {:bulk_erase_with_data, hashes, paths})}
  end

  def handle_event("confirm_action", _params, socket) do
    case socket.assigns.confirm_action do
      {:erase, hash} ->
        case @commands.erase(hash) do
          :ok ->
            torrents = Enum.reject(socket.assigns.torrents, &(&1.hash == hash))
            selected = MapSet.delete(socket.assigns.selected_hashes, hash)

            socket =
              socket
              |> assign(:torrents, torrents)
              |> assign(:selected_hashes, selected)
              |> assign(:confirm_action, nil)
              |> assign_global_stats(torrents)
              |> assign(:status_counts, status_counts(torrents))
              |> put_flash(:info, "Torrent removed")

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> assign(:confirm_action, nil)
              |> put_flash(:error, "Failed to remove: #{inspect(reason)}")

            {:noreply, socket}
        end

      {:bulk_erase, hashes} ->
        results = Enum.map(hashes, fn h -> {h, @commands.erase(h)} end)
        succeeded = for {h, :ok} <- results, do: h
        any_failed = length(succeeded) < length(hashes)

        succeeded_set = MapSet.new(succeeded)
        torrents = Enum.reject(socket.assigns.torrents, &MapSet.member?(succeeded_set, &1.hash))

        socket =
          socket
          |> assign(:torrents, torrents)
          |> assign(:selected_hashes, MapSet.new())
          |> assign(:confirm_action, nil)
          |> assign_global_stats(torrents)
          |> assign(:status_counts, status_counts(torrents))

        socket =
          if any_failed do
            put_flash(socket, :error, "Some torrents failed to remove")
          else
            put_flash(socket, :info, "Torrents removed")
          end

        {:noreply, socket}

      {:erase_with_data, hash, _path} ->
        case @commands.erase_with_data(hash) do
          :ok ->
            torrents = Enum.reject(socket.assigns.torrents, &(&1.hash == hash))
            selected = MapSet.delete(socket.assigns.selected_hashes, hash)

            socket =
              socket
              |> assign(:torrents, torrents)
              |> assign(:selected_hashes, selected)
              |> assign(:confirm_action, nil)
              |> assign_global_stats(torrents)
              |> assign(:status_counts, status_counts(torrents))
              |> put_flash(:info, "Torrent removed and files deleted")

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> assign(:confirm_action, nil)
              |> put_flash(:error, format_erase_error(reason))

            {:noreply, socket}
        end

      {:bulk_erase_with_data, hashes, _paths} ->
        {:ok, succeeded, _failed} = @commands.erase_many_with_data(hashes)
        any_failed = length(succeeded) < length(hashes)

        succeeded_set = MapSet.new(succeeded)
        torrents = Enum.reject(socket.assigns.torrents, &MapSet.member?(succeeded_set, &1.hash))

        socket =
          socket
          |> assign(:torrents, torrents)
          |> assign(:selected_hashes, MapSet.new())
          |> assign(:confirm_action, nil)
          |> assign_global_stats(torrents)
          |> assign(:status_counts, status_counts(torrents))

        socket =
          if any_failed do
            put_flash(socket, :error, "Some torrents failed to remove")
          else
            put_flash(socket, :info, "Torrents removed and files deleted")
          end

        {:noreply, socket}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_action, nil)}
  end

  def handle_event("show_add_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
  end

  def handle_event("hide_add_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, false)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("submit_file", params, socket) do
    dir =
      case Map.get(params, "download_dir", "") do
        "" -> nil
        d -> d
      end

    results =
      consume_uploaded_entries(socket, :torrent_file, fn %{path: path}, _entry ->
        File.read(path)
      end)

    case results do
      [binary] when is_binary(binary) ->
        case @commands.load_raw(binary, maybe_add_directory([], dir)) do
          :ok ->
            {:noreply,
             socket
             |> assign(:show_add_modal, false)
             |> put_flash(:success, "Torrent added")}

          {:error, reason} ->
            send_update(TaniwhaWeb.AddTorrentComponent,
              id: "add-torrent-modal",
              error: format_add_error(reason),
              loading: false
            )

            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :torrent_file, ref)}
  end

  def handle_event(
        "update_selection",
        %{"hashes" => hashes, "focused_hash" => focused},
        socket
      ) do
    selected = MapSet.new(hashes)
    old_hash = socket.assigns.selected_hash

    socket =
      if focused != old_hash do
        unsubscribe_detail(old_hash)

        if is_binary(focused) and byte_size(focused) > 0 do
          Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:#{focused}")
          socket |> assign(:selected_hash, focused) |> reset_detail_assigns()
        else
          socket |> assign(:selected_hash, nil) |> reset_detail_assigns()
        end
      else
        socket
      end

    {:noreply, assign(socket, :selected_hashes, selected)}
  end

  def handle_event("close_panel", _params, socket) do
    unsubscribe_detail(socket.assigns.selected_hash)
    {:noreply, socket |> assign(:selected_hash, nil) |> reset_detail_assigns()}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = parse_tab(tab)
    {:noreply, socket |> assign(:active_tab, tab_atom) |> load_tab(tab_atom)}
  end

  def handle_event(
        "set_file_priority",
        %{"hash" => hash, "index" => index, "priority" => priority},
        socket
      ) do
    @commands.set_file_priority(hash, String.to_integer(index), String.to_integer(priority))
    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    cond do
      socket.assigns.confirm_action != nil ->
        {:noreply, assign(socket, :confirm_action, nil)}

      socket.assigns.show_add_modal ->
        {:noreply, assign(socket, :show_add_modal, false)}

      socket.assigns.selected_hash ->
        unsubscribe_detail(socket.assigns.selected_hash)
        {:noreply, socket |> assign(:selected_hash, nil) |> reset_detail_assigns()}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  def handle_event("bulk_start", _params, socket) do
    any_failed =
      Enum.any?(socket.assigns.selected_hashes, fn hash ->
        @commands.start(hash) != :ok
      end)

    socket =
      if any_failed, do: put_flash(socket, :error, "Some torrents failed to start"), else: socket

    {:noreply, socket}
  end

  def handle_event("bulk_stop", _params, socket) do
    any_failed =
      Enum.any?(socket.assigns.selected_hashes, fn hash ->
        @commands.stop(hash) != :ok
      end)

    socket =
      if any_failed, do: put_flash(socket, :error, "Some torrents failed to stop"), else: socket

    {:noreply, socket}
  end

  def handle_event("bulk_pause", _params, socket) do
    any_failed =
      Enum.any?(socket.assigns.selected_hashes, fn hash ->
        @commands.pause(hash) != :ok
      end)

    socket =
      if any_failed, do: put_flash(socket, :error, "Some torrents failed to pause"), else: socket

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Public helpers (called from template)
  # ---------------------------------------------------------------------------

  @doc false
  @spec visible_torrents(
          [Torrent.t()],
          String.t(),
          atom(),
          atom() | String.t(),
          atom() | String.t(),
          atom(),
          atom()
        ) :: [Torrent.t()]
  def visible_torrents(torrents, search, filter, tracker_filter, label_filter, sort_by, sort_dir) do
    torrents
    |> filter_by_status(filter)
    |> filter_by_tracker(tracker_filter)
    |> filter_by_label(label_filter)
    |> filter_by_search(search)
    |> sort_torrents(sort_by, sort_dir)
  end

  @doc false
  @spec label_groups([Torrent.t()]) :: [{String.t(), non_neg_integer()}]
  def label_groups(torrents) do
    torrents
    |> Enum.reject(&is_nil(&1.label))
    |> Enum.group_by(& &1.label)
    |> Enum.map(fn {label, ts} -> {label, length(ts)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc false
  @spec status_counts([Torrent.t()]) :: map()
  def status_counts(torrents) do
    base = %{
      all: length(torrents),
      downloading: 0,
      seeding: 0,
      stopped: 0,
      checking: 0,
      paused: 0
    }

    Enum.reduce(torrents, base, fn t, acc ->
      Map.update(acc, Torrent.status(t), 1, &(&1 + 1))
    end)
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

  @spec filter_by_tracker([Torrent.t()], atom() | String.t()) :: [Torrent.t()]
  # TODO: implement when Torrent struct exposes tracker URLs
  defp filter_by_tracker(torrents, :all), do: torrents
  defp filter_by_tracker(torrents, _domain), do: torrents

  @spec filter_by_label([Torrent.t()], atom() | String.t()) :: [Torrent.t()]
  defp filter_by_label(torrents, :all), do: torrents
  defp filter_by_label(torrents, label), do: Enum.filter(torrents, &(&1.label == label))

  @spec parse_filter(String.t()) :: atom()
  defp parse_filter("all"), do: :all
  defp parse_filter("downloading"), do: :downloading
  defp parse_filter("seeding"), do: :seeding
  defp parse_filter("stopped"), do: :stopped
  defp parse_filter(_), do: :all

  @spec parse_tracker_filter(String.t()) :: :all | String.t()
  defp parse_tracker_filter("all"), do: :all
  defp parse_tracker_filter(domain), do: domain

  @spec parse_label_filter(String.t()) :: :all | String.t()
  defp parse_label_filter("all"), do: :all
  defp parse_label_filter(label), do: label

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

  @spec reset_detail_assigns(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp reset_detail_assigns(socket) do
    socket
    |> assign(:active_tab, :general)
    |> assign(:detail_files, %AsyncResult{})
    |> assign(:detail_peers, %AsyncResult{})
    |> assign(:detail_trackers, %AsyncResult{})
  end

  @spec unsubscribe_detail(String.t() | nil) :: :ok
  defp unsubscribe_detail(nil), do: :ok

  defp unsubscribe_detail(hash) do
    Phoenix.PubSub.unsubscribe(Taniwha.PubSub, "torrents:#{hash}")
  end

  @spec load_tab(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  defp load_tab(socket, :files),
    do: load_async_tab(socket, :detail_files, &@commands.list_files/1)

  defp load_tab(socket, :peers),
    do: load_async_tab(socket, :detail_peers, &@commands.list_peers/1)

  defp load_tab(socket, :trackers),
    do: load_async_tab(socket, :detail_trackers, &@commands.list_trackers/1)

  defp load_tab(socket, :general), do: socket

  @spec load_async_tab(
          Phoenix.LiveView.Socket.t(),
          atom(),
          (String.t() -> {:ok, list()} | {:error, term()})
        ) :: Phoenix.LiveView.Socket.t()
  defp load_async_tab(socket, field, command) do
    result = Map.get(socket.assigns, field)

    if result.loading != nil or result.ok? do
      socket
    else
      hash = socket.assigns.selected_hash

      assign_async(socket, [field], fn ->
        case command.(hash) do
          {:ok, data} -> {:ok, %{field => data}}
          {:error, r} -> {:error, r}
        end
      end)
    end
  end

  @spec parse_tab(String.t()) :: :general | :files | :peers | :trackers
  defp parse_tab("files"), do: :files
  defp parse_tab("peers"), do: :peers
  defp parse_tab("trackers"), do: :trackers
  defp parse_tab(_), do: :general

  @spec format_erase_error(term()) :: String.t()
  defp format_erase_error(:downloads_dir_not_configured),
    do: "File deletion is not configured. Set the TANIWHA_DOWNLOADS_DIR environment variable."

  defp format_erase_error(:no_base_path),
    do: "Torrent has no base path — it may not have been started yet."

  defp format_erase_error({:path_outside_downloads_dir, torrent_path, configured_dir}),
    do:
      "Torrent path is outside the configured downloads directory. " <>
        "Torrent path: #{torrent_path}. Configured directory: #{configured_dir}."

  defp format_erase_error(reason), do: "Failed to remove: #{inspect(reason)}"

  @spec maybe_add_directory(keyword(), String.t() | nil) :: keyword()
  defp maybe_add_directory(opts, nil), do: opts
  defp maybe_add_directory(opts, dir), do: Keyword.put(opts, :directory, dir)

  @spec find_base_path([Torrent.t()], String.t()) :: String.t() | nil
  defp find_base_path(torrents, hash) do
    case Enum.find(torrents, &(&1.hash == hash)) do
      nil -> nil
      torrent -> torrent.base_path
    end
  end

  @spec maybe_close_detail_panel(Phoenix.LiveView.Socket.t(), MapSet.t()) ::
          Phoenix.LiveView.Socket.t()
  defp maybe_close_detail_panel(socket, removed_hashes) do
    hash = socket.assigns.selected_hash

    if hash != nil and MapSet.member?(removed_hashes, hash) do
      unsubscribe_detail(hash)

      socket
      |> assign(:selected_hash, nil)
      |> reset_detail_assigns()
      |> put_flash(:info, "The selected torrent was removed")
    else
      socket
    end
  end
end
