defmodule Taniwha.State.Poller do
  @moduledoc """
  Periodic diff engine for rtorrent state.

  On each poll cycle, fetches all torrents via `Taniwha.Commands`, diffs the
  result against the ETS cache in `Taniwha.State.Store`, writes changes back
  to the cache, and broadcasts diffs over `Phoenix.PubSub` so all connected
  clients receive live updates without polling themselves.

  ## PubSub topics

  - `"torrents:list"` — receives `{:torrent_diffs, diffs}` (full diff list)
  - `"torrents:{hash}"` — receives `{:torrent_updated, torrent}` for each
    `:added` or `:updated` torrent

  ## No-overlap guarantee

  The next poll is scheduled at the **end** of `handle_info/2` after the
  current poll completes. Polls cannot overlap.

  ## Dependency injection

  The commands module is injected at compile time via application config,
  enabling Mox-based mocking in tests:

      # config/test.exs
      config :taniwha, commands: Taniwha.MockCommands
  """

  use GenServer

  require Logger

  alias Taniwha.State.Store
  alias Taniwha.Torrent

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  @diff_fields ~w(upload_rate download_rate completed_bytes state is_active is_hash_checking peers_connected ratio complete)a

  # ── Public API ────────────────────────────────────────────────────────────

  @doc "Starts the Poller GenServer, registering it under its module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Updates the polling interval at runtime.

  Takes effect on the next scheduled poll. Does not affect the currently
  running or pending timer.
  """
  @spec set_interval(pos_integer()) :: :ok
  def set_interval(interval) do
    GenServer.cast(__MODULE__, {:set_interval, interval})
  end

  @doc """
  Computes the diff between old and new torrent maps.

  Returns a list of diff tuples:

  - `{:added, torrent}` — hash present in `new_map` but not in `old_map`
  - `{:removed, hash}` — hash present in `old_map` but not in `new_map`
  - `{:updated, torrent}` — hash present in both but at least one diff field
    changed

  Only changes to fields in `@diff_fields` trigger an `:updated` entry.
  Non-diff fields (e.g. `name`, `base_path`) are intentionally ignored to
  avoid noisy updates.
  """
  @spec compute_diffs(%{String.t() => Torrent.t()}, %{String.t() => Torrent.t()}) ::
          [{:added, Torrent.t()} | {:removed, String.t()} | {:updated, Torrent.t()}]
  def compute_diffs(old_map, new_map) do
    added =
      for {hash, torrent} <- new_map,
          not Map.has_key?(old_map, hash),
          do: {:added, torrent}

    removed =
      for {hash, _torrent} <- old_map,
          not Map.has_key?(new_map, hash),
          do: {:removed, hash}

    updated =
      for {hash, new_torrent} <- new_map,
          old_torrent = Map.get(old_map, hash),
          old_torrent != nil,
          diff_fields_changed?(old_torrent, new_torrent),
          do: {:updated, new_torrent}

    added ++ removed ++ updated
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    interval =
      Keyword.get(
        opts,
        :poll_interval,
        Application.get_env(:taniwha, :poll_interval, 5_000)
      )

    schedule_poll(interval)
    {:ok, %{interval: interval, consecutive_failures: 0}}
  end

  @impl true
  def handle_info(:poll, %{interval: interval} = state) do
    new_state =
      case @commands.get_all_torrents("") do
        {:ok, torrents} ->
          new_map = Map.new(torrents, &{&1.hash, &1})
          old_map = Map.new(Store.get_all_torrents(), &{&1.hash, &1})
          diffs = compute_diffs(old_map, new_map)
          apply_diffs(diffs)
          maybe_broadcast(diffs)
          %{state | consecutive_failures: 0}

        {:error, reason} ->
          Logger.warning("Poller: failed to fetch torrents: #{inspect(reason)}")
          %{state | consecutive_failures: state.consecutive_failures + 1}
      end

    schedule_poll(interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_interval, interval}, state) do
    {:noreply, %{state | interval: interval}}
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  @spec diff_fields_changed?(Torrent.t(), Torrent.t()) :: boolean()
  defp diff_fields_changed?(old, new) do
    Enum.any?(@diff_fields, fn field ->
      Map.get(old, field) != Map.get(new, field)
    end)
  end

  @spec apply_diffs([{:added, Torrent.t()} | {:removed, String.t()} | {:updated, Torrent.t()}]) ::
          :ok
  defp apply_diffs(diffs) do
    Enum.each(diffs, fn
      {:added, torrent} -> Store.put_torrent(torrent)
      {:updated, torrent} -> Store.put_torrent(torrent)
      {:removed, hash} -> Store.delete_torrent(hash)
    end)
  end

  @spec maybe_broadcast([
          {:added, Torrent.t()} | {:removed, String.t()} | {:updated, Torrent.t()}
        ]) :: :ok
  defp maybe_broadcast([]), do: :ok

  defp maybe_broadcast(diffs) do
    Phoenix.PubSub.broadcast(Taniwha.PubSub, "torrents:list", {:torrent_diffs, diffs})

    Enum.each(diffs, fn
      {type, torrent} when type in [:added, :updated] ->
        Phoenix.PubSub.broadcast(
          Taniwha.PubSub,
          "torrents:#{torrent.hash}",
          {:torrent_updated, torrent}
        )

      {:removed, _hash} ->
        :ok
    end)
  end

  @spec schedule_poll(pos_integer()) :: reference()
  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
