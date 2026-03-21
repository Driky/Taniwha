defmodule Taniwha.State.Store do
  @moduledoc """
  ETS-backed torrent state cache.

  Owns a named ETS table (`:taniwha_state`) that lives as long as this GenServer.
  All reads and writes bypass the GenServer mailbox and call `:ets` directly for
  throughput. The table is `:public` with `read_concurrency: true` so the web layer
  and the Poller can read it without going through this process.

  If this GenServer crashes, the table is lost. The supervisor restarts it and the
  Poller repopulates it on the next poll cycle.
  """

  use GenServer

  alias Taniwha.Torrent

  @table :taniwha_state

  @doc "Starts the Store and creates the named ETS table."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # ── Public API (direct ETS calls, no GenServer mailbox) ──────────────────

  @doc "Returns all torrents currently in the store, in unspecified order."
  @spec get_all_torrents() :: [Torrent.t()]
  def get_all_torrents do
    :ets.foldl(fn {_hash, torrent}, acc -> [torrent | acc] end, [], @table)
  end

  @doc "Fetches a single torrent by hash. Returns `{:error, :not_found}` if absent."
  @spec get_torrent(String.t()) :: {:ok, Torrent.t()} | {:error, :not_found}
  def get_torrent(hash) do
    case :ets.lookup(@table, hash) do
      [{^hash, torrent}] -> {:ok, torrent}
      [] -> {:error, :not_found}
    end
  end

  @doc "Inserts or replaces a torrent in the store."
  @spec put_torrent(Torrent.t()) :: :ok
  def put_torrent(%Torrent{hash: hash} = torrent) do
    :ets.insert(@table, {hash, torrent})
    :ok
  end

  @doc "Removes a torrent by hash. No-op if the hash is not present."
  @spec delete_torrent(String.t()) :: :ok
  def delete_torrent(hash) do
    :ets.delete(@table, hash)
    :ok
  end

  @doc "Removes all entries from the store."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Returns the number of torrents currently in the store."
  @spec count() :: non_neg_integer()
  def count, do: :ets.info(@table, :size)

  # ── GenServer callback ────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
