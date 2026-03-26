defmodule Taniwha.Commands do
  @moduledoc """
  High-level rtorrent command API.

  This is the **only** public entry point for interacting with rtorrent. No
  module outside the domain layer may call `Taniwha.RPC.Client` directly.

  The RPC client is injected at compile time via application config, which
  enables Mox-based mocking in tests:

      # config/test.exs
      config :taniwha, rpc_client: Taniwha.RPC.MockClient

  ## Observability

  Each public function wraps its work in an OpenTelemetry span named
  `taniwha.commands.{function_name}`. Hash-bearing functions also set the
  `torrent.hash` attribute. Because this module is a plain module (not a
  GenServer), all spans automatically inherit the caller's OTel context,
  forming a clean trace hierarchy:

      HTTP span → taniwha.commands.start → taniwha.rpc.call

  See `docs/observability.md` for the full attribute catalogue.
  """

  @behaviour Taniwha.CommandsBehaviour

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

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
    Tracer.with_span "taniwha.commands.list_hashes",
                     %{attributes: %{"command.name": "list_hashes"}} do
      @rpc_client.call("download_list", [view])
    end
  end

  @doc """
  Fetches a single torrent by its info-hash.

  Issues a `system.multicall` for all `Torrent.rpc_fields/0` values and
  constructs a `Torrent` struct from the results.
  """
  @spec get_torrent(String.t()) :: {:ok, Torrent.t()} | {:error, term()}
  def get_torrent(hash) do
    Tracer.with_span "taniwha.commands.get_torrent",
                     %{attributes: %{"command.name": "get_torrent", "torrent.hash": hash}} do
      calls = Enum.map(Torrent.rpc_fields(), fn field -> {field, [hash]} end)

      with {:ok, results} <- @rpc_client.multicall(calls) do
        values = Enum.map(results, fn [v] -> v end)
        {:ok, Torrent.from_rpc_values(hash, values)}
      end
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
    Tracer.with_span "taniwha.commands.get_all_torrents",
                     %{attributes: %{"command.name": "get_all_torrents"}} do
      with {:ok, hashes} <- list_hashes(view),
           {:ok, results} <- fetch_all_torrent_data(hashes) do
        {:ok, build_torrents(hashes, results)}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle commands
  # ---------------------------------------------------------------------------

  @doc "Starts a torrent. Returns `:ok` on success."
  @impl Taniwha.CommandsBehaviour
  @spec start(String.t()) :: :ok | {:error, term()}
  def start(hash) do
    Tracer.with_span "taniwha.commands.start",
                     %{attributes: %{"command.name": "start", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "start", torrent_hash: hash)
      run_lifecycle("d.start", hash)
    end
  end

  @doc "Stops a torrent. Returns `:ok` on success."
  @impl Taniwha.CommandsBehaviour
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(hash) do
    Tracer.with_span "taniwha.commands.stop",
                     %{attributes: %{"command.name": "stop", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "stop", torrent_hash: hash)
      run_lifecycle("d.stop", hash)
    end
  end

  @doc "Closes a torrent (releases tracker connections). Returns `:ok` on success."
  @spec close(String.t()) :: :ok | {:error, term()}
  def close(hash) do
    Tracer.with_span "taniwha.commands.close",
                     %{attributes: %{"command.name": "close", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "close", torrent_hash: hash)
      run_lifecycle("d.close", hash)
    end
  end

  @doc "Erases a torrent from rtorrent. Returns `:ok` on success."
  @impl Taniwha.CommandsBehaviour
  @spec erase(String.t()) :: :ok | {:error, term()}
  def erase(hash) do
    Tracer.with_span "taniwha.commands.erase",
                     %{attributes: %{"command.name": "erase", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "erase", torrent_hash: hash)
      run_lifecycle("d.erase", hash)
    end
  end

  @impl Taniwha.CommandsBehaviour
  @doc "Pauses a torrent. Returns `:ok` on success."
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(hash) do
    Tracer.with_span "taniwha.commands.pause",
                     %{attributes: %{"command.name": "pause", "torrent.hash": hash}} do
      run_lifecycle("d.pause", hash)
    end
  end

  @doc "Resumes a paused torrent. Returns `:ok` on success."
  @spec resume(String.t()) :: :ok | {:error, term()}
  def resume(hash) do
    Tracer.with_span "taniwha.commands.resume",
                     %{attributes: %{"command.name": "resume", "torrent.hash": hash}} do
      run_lifecycle("d.resume", hash)
    end
  end

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
    Tracer.with_span "taniwha.commands.load_url",
                     %{attributes: %{"command.name": "load_url"}} do
      Logger.info("Command executed", command: "load_url")
      @rpc_client.call("load.start", ["", url]) |> ok_on_zero()
    end
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
    Tracer.with_span "taniwha.commands.load_raw",
                     %{attributes: %{"command.name": "load_raw"}} do
      Logger.info("Command executed", command: "load_raw")
      @rpc_client.call("load.raw_start", ["", {:base64, data}]) |> ok_on_zero()
    end
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
    Tracer.with_span "taniwha.commands.list_files",
                     %{attributes: %{"command.name": "list_files", "torrent.hash": hash}} do
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
  end

  @doc """
  Lists the peers connected to a torrent.

  Calls rtorrent's `p.multicall` command. Returns `Peer` structs in the order
  rtorrent reports them.
  """
  @impl Taniwha.CommandsBehaviour
  @spec list_peers(String.t()) :: {:ok, [Peer.t()]} | {:error, term()}
  def list_peers(hash) do
    Tracer.with_span "taniwha.commands.list_peers",
                     %{attributes: %{"command.name": "list_peers", "torrent.hash": hash}} do
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
  end

  @doc """
  Lists the trackers associated with a torrent.

  Calls rtorrent's `t.multicall` command. Returns `Tracker` structs in the
  order rtorrent reports them.
  """
  @impl Taniwha.CommandsBehaviour
  @spec list_trackers(String.t()) :: {:ok, [Tracker.t()]} | {:error, term()}
  def list_trackers(hash) do
    Tracer.with_span "taniwha.commands.list_trackers",
                     %{attributes: %{"command.name": "list_trackers", "torrent.hash": hash}} do
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
    Tracer.with_span "taniwha.commands.set_file_priority",
                     %{attributes: %{"command.name": "set_file_priority", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "set_file_priority", torrent_hash: hash)
      @rpc_client.call("f.priority.set", ["#{hash}:f#{index}", priority]) |> ok_on_zero()
    end
  end

  # ---------------------------------------------------------------------------
  # Global stats
  # ---------------------------------------------------------------------------

  @doc "Returns the current global upload rate in bytes per second."
  @spec global_up_rate() :: {:ok, non_neg_integer()} | {:error, term()}
  def global_up_rate do
    Tracer.with_span "taniwha.commands.global_up_rate",
                     %{attributes: %{"command.name": "global_up_rate"}} do
      @rpc_client.call("throttle.global_up.rate", [])
    end
  end

  @doc "Returns the current global download rate in bytes per second."
  @spec global_down_rate() :: {:ok, non_neg_integer()} | {:error, term()}
  def global_down_rate do
    Tracer.with_span "taniwha.commands.global_down_rate",
                     %{attributes: %{"command.name": "global_down_rate"}} do
      @rpc_client.call("throttle.global_down.rate", [])
    end
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
