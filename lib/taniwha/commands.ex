defmodule Taniwha.Commands do
  @moduledoc """
  High-level rtorrent command API.

  This is the **only** public entry point for interacting with rtorrent. No
  module outside the domain layer may call `Taniwha.RPC.Client` directly.

  The RPC client is injected at compile time via application config, which
  enables Mox-based mocking in tests:

      # config/test.exs
      config :taniwha, rpc_client: Taniwha.RPC.MockClient
  """

  @behaviour Taniwha.CommandsBehaviour

  alias Taniwha.Peer
  alias Taniwha.Torrent
  alias Taniwha.Tracker
  alias Taniwha.TorrentFile

  @rpc_client Application.compile_env(:taniwha, :rpc_client, Taniwha.RPC.Client)

  @torrent_fields_count length(Taniwha.Torrent.rpc_fields())

  @file_fields [
    "f.path=",
    "f.size_bytes=",
    "f.priority=",
    "f.completed_chunks=",
    "f.size_chunks="
  ]

  @peer_fields [
    "p.address=",
    "p.port=",
    "p.client_version=",
    "p.down_rate=",
    "p.up_rate=",
    "p.completed_percent="
  ]

  @tracker_fields [
    "t.url=",
    "t.is_enabled=",
    "t.scrape_complete=",
    "t.scrape_incomplete=",
    "t.normal_interval="
  ]

  # ---------------------------------------------------------------------------
  # Torrent listing
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of torrent info-hashes in the given rtorrent view.

  Defaults to `""` which returns all torrents in the default view.
  """
  @spec list_hashes(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_hashes(view \\ "") do
    @rpc_client.call("download_list", [view])
  end

  @doc """
  Fetches a single torrent by its info-hash.

  Issues a `system.multicall` for all `Torrent.rpc_fields/0` values and
  constructs a `Torrent` struct from the results.
  """
  @spec get_torrent(String.t()) :: {:ok, Torrent.t()} | {:error, term()}
  def get_torrent(hash) do
    calls = Enum.map(Torrent.rpc_fields(), fn field -> {field, [hash]} end)

    with {:ok, results} <- @rpc_client.multicall(calls) do
      values = Enum.map(results, fn [v] -> v end)
      {:ok, Torrent.from_rpc_values(hash, values)}
    end
  end

  @doc """
  Fetches all torrents in the given view in a single batched multicall.

  Calls `list_hashes/1` first, then issues one `system.multicall` covering
  every field for every torrent. Returns `{:ok, []}` if no torrents exist.
  """
  @impl Taniwha.CommandsBehaviour
  @spec get_all_torrents(String.t()) :: {:ok, [Torrent.t()]} | {:error, term()}
  def get_all_torrents(view \\ "") do
    with {:ok, hashes} <- list_hashes(view),
         {:ok, results} <- fetch_all_torrent_data(hashes) do
      {:ok, build_torrents(hashes, results)}
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle commands
  # ---------------------------------------------------------------------------

  @doc "Starts a torrent. Returns `:ok` on success."
  @impl Taniwha.CommandsBehaviour
  @spec start(String.t()) :: :ok | {:error, term()}
  def start(hash), do: run_lifecycle("d.start", hash)

  @doc "Stops a torrent. Returns `:ok` on success."
  @impl Taniwha.CommandsBehaviour
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(hash), do: run_lifecycle("d.stop", hash)

  @doc "Closes a torrent (releases tracker connections). Returns `:ok` on success."
  @spec close(String.t()) :: :ok | {:error, term()}
  def close(hash), do: run_lifecycle("d.close", hash)

  @doc "Erases a torrent from rtorrent. Returns `:ok` on success."
  @impl Taniwha.CommandsBehaviour
  @spec erase(String.t()) :: :ok | {:error, term()}
  def erase(hash), do: run_lifecycle("d.erase", hash)

  @impl Taniwha.CommandsBehaviour
  @doc "Pauses a torrent. Returns `:ok` on success."
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(hash), do: run_lifecycle("d.pause", hash)

  @doc "Resumes a paused torrent. Returns `:ok` on success."
  @spec resume(String.t()) :: :ok | {:error, term()}
  def resume(hash), do: run_lifecycle("d.resume", hash)

  # ---------------------------------------------------------------------------
  # Load commands
  # ---------------------------------------------------------------------------

  @doc """
  Loads and starts a torrent from a URL.

  Passes an empty string as the target (uses rtorrent's default download
  directory).
  """
  @impl Taniwha.CommandsBehaviour
  @spec load_url(String.t()) :: :ok | {:error, term()}
  def load_url(url) do
    @rpc_client.call("load.start", ["", url]) |> ok_on_zero()
  end

  @doc """
  Loads and starts a torrent from raw binary data (e.g. an uploaded `.torrent`
  file).

  Passes an empty string as the target (uses rtorrent's default download
  directory).
  """
  @impl Taniwha.CommandsBehaviour
  @spec load_raw(binary()) :: :ok | {:error, term()}
  def load_raw(data) do
    @rpc_client.call("load.raw_start", ["", {:base64, data}]) |> ok_on_zero()
  end

  # ---------------------------------------------------------------------------
  # File operations
  # ---------------------------------------------------------------------------

  @doc """
  Lists the files within a torrent.

  Calls rtorrent's `f.multicall` command. Returns `TorrentFile` structs in
  the order rtorrent reports them (zero-based index order).
  """
  @impl Taniwha.CommandsBehaviour
  @spec list_files(String.t()) :: {:ok, [TorrentFile.t()]} | {:error, term()}
  def list_files(hash) do
    with {:ok, files} <- @rpc_client.call("f.multicall", [hash, "" | @file_fields]) do
      result =
        Enum.map(files, fn [path, size, priority, completed, total] ->
          %TorrentFile{
            path: path,
            size: size,
            priority: priority,
            completed_chunks: completed,
            total_chunks: total
          }
        end)

      {:ok, result}
    end
  end

  @doc """
  Lists the peers connected to a torrent.

  Calls rtorrent's `p.multicall` command. Returns `Peer` structs in the order
  rtorrent reports them.
  """
  @impl Taniwha.CommandsBehaviour
  @spec list_peers(String.t()) :: {:ok, [Peer.t()]} | {:error, term()}
  def list_peers(hash) do
    with {:ok, peers} <- @rpc_client.call("p.multicall", [hash, "" | @peer_fields]) do
      result =
        Enum.map(peers, fn [addr, port, client, down, up, pct] ->
          %Peer{
            address: addr,
            port: port,
            client_version: client,
            down_rate: down,
            up_rate: up,
            completed_percent: pct * 1.0
          }
        end)

      {:ok, result}
    end
  end

  @doc """
  Lists the trackers associated with a torrent.

  Calls rtorrent's `t.multicall` command. Returns `Tracker` structs in the
  order rtorrent reports them.
  """
  @impl Taniwha.CommandsBehaviour
  @spec list_trackers(String.t()) :: {:ok, [Tracker.t()]} | {:error, term()}
  def list_trackers(hash) do
    with {:ok, trackers} <- @rpc_client.call("t.multicall", [hash, "" | @tracker_fields]) do
      result =
        Enum.map(trackers, fn [url, enabled, complete, incomplete, interval] ->
          %Tracker{
            url: url,
            is_enabled: enabled == 1,
            scrape_complete: complete,
            scrape_incomplete: incomplete,
            normal_interval: interval
          }
        end)

      {:ok, result}
    end
  end

  @doc """
  Sets the download priority for a specific file within a torrent.

  `index` is the zero-based file index within the torrent.
  `priority` is an integer: `0` = skip, `1` = normal, `2` = high.
  """
  @impl Taniwha.CommandsBehaviour
  @spec set_file_priority(String.t(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, term()}
  def set_file_priority(hash, index, priority) do
    @rpc_client.call("f.priority.set", ["#{hash}:f#{index}", priority]) |> ok_on_zero()
  end

  # ---------------------------------------------------------------------------
  # Global stats
  # ---------------------------------------------------------------------------

  @doc "Returns the current global upload rate in bytes per second."
  @spec global_up_rate() :: {:ok, non_neg_integer()} | {:error, term()}
  def global_up_rate do
    @rpc_client.call("throttle.global_up.rate", [])
  end

  @doc "Returns the current global download rate in bytes per second."
  @spec global_down_rate() :: {:ok, non_neg_integer()} | {:error, term()}
  def global_down_rate do
    @rpc_client.call("throttle.global_down.rate", [])
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec run_lifecycle(String.t(), String.t()) :: :ok | {:error, term()}
  defp run_lifecycle(method, hash) do
    @rpc_client.call(method, [hash]) |> ok_on_zero()
  end

  @spec ok_on_zero({:ok, 0} | {:ok, term()} | {:error, term()}) :: :ok | {:error, term()}
  defp ok_on_zero({:ok, 0}), do: :ok
  defp ok_on_zero(other), do: other

  @spec fetch_all_torrent_data([String.t()]) :: {:ok, [term()]} | {:error, term()}
  defp fetch_all_torrent_data([]), do: {:ok, []}

  defp fetch_all_torrent_data(hashes) do
    calls = for hash <- hashes, field <- Torrent.rpc_fields(), do: {field, [hash]}
    @rpc_client.multicall(calls)
  end

  @spec build_torrents([String.t()], [term()]) :: [Torrent.t()]
  defp build_torrents(hashes, results) do
    results
    |> Enum.map(fn [v] -> v end)
    |> Enum.chunk_every(@torrent_fields_count)
    |> Enum.zip(hashes)
    |> Enum.map(fn {values, hash} -> Torrent.from_rpc_values(hash, values) end)
  end
end
