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
  alias Taniwha.State.Store
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

  @doc """
  Erases a torrent from rtorrent **and** deletes its downloaded files.

  Requires `config :taniwha, downloads_dir: "/path/to/downloads"` (set via the
  `TANIWHA_DOWNLOADS_DIR` environment variable). The files are deleted first via
  `Taniwha.FileSystem.safe_delete/2` — if that fails, the torrent record is
  preserved in rtorrent. `d.erase` is only called once file deletion succeeds,
  keeping rtorrent state and the filesystem consistent.

  Possible errors:
    * `{:error, :downloads_dir_not_configured}` — no downloads_dir in config
    * `{:error, :no_base_path}` — torrent has no base path (not started yet)
    * `{:error, {:path_outside_downloads_dir, base_path, downloads_dir}}` — base_path escapes downloads_dir
    * `{:error, posix}` — filesystem error from `File.rm_rf/1`
    * `{:error, term}` — RPC error from rtorrent
  """
  @impl Taniwha.CommandsBehaviour
  @spec erase_with_data(String.t()) :: :ok | {:error, term()}
  def erase_with_data(hash) do
    Tracer.with_span "taniwha.commands.erase_with_data",
                     %{attributes: %{"command.name": "erase_with_data", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "erase_with_data", torrent_hash: hash)

      case Application.get_env(:taniwha, :downloads_dir) do
        nil ->
          {:error, :downloads_dir_not_configured}

        downloads_dir ->
          with {:ok, base_path} <- fetch_base_path(hash),
               :ok <- Taniwha.FileSystem.safe_delete(base_path, downloads_dir) do
            run_lifecycle("d.erase", hash)
          end
      end
    end
  end

  @doc """
  Erases multiple torrents from rtorrent.

  Calls `erase/1` for each hash. Returns `{:ok, ok_hashes, error_hashes}`.
  """
  @impl Taniwha.CommandsBehaviour
  @spec erase_many([String.t()]) :: {:ok, [String.t()], [String.t()]}
  def erase_many(hashes) do
    results = Enum.map(hashes, fn h -> {h, erase(h)} end)
    ok = for {h, :ok} <- results, do: h
    errors = for {h, {:error, _}} <- results, do: h
    {:ok, ok, errors}
  end

  @doc """
  Erases multiple torrents from rtorrent and deletes their downloaded files.

  Calls `erase_with_data/1` for each hash. Returns `{:ok, ok_hashes, error_hashes}`.
  """
  @impl Taniwha.CommandsBehaviour
  @spec erase_many_with_data([String.t()]) :: {:ok, [String.t()], [String.t()]}
  def erase_many_with_data(hashes) do
    results = Enum.map(hashes, fn h -> {h, erase_with_data(h)} end)
    ok = for {h, :ok} <- results, do: h
    errors = for {h, {:error, _}} <- results, do: h
    {:ok, ok, errors}
  end

  @impl Taniwha.CommandsBehaviour
  @doc "Pauses a torrent. Returns `:ok` on success."
  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(hash) do
    Tracer.with_span "taniwha.commands.pause",
                     %{attributes: %{"command.name": "pause", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "pause", torrent_hash: hash)
      run_lifecycle("d.pause", hash)
    end
  end

  @doc "Resumes a paused torrent. Returns `:ok` on success."
  @spec resume(String.t()) :: :ok | {:error, term()}
  def resume(hash) do
    Tracer.with_span "taniwha.commands.resume",
                     %{attributes: %{"command.name": "resume", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "resume", torrent_hash: hash)
      run_lifecycle("d.resume", hash)
    end
  end

  # ---------------------------------------------------------------------------
  # Load commands
  # ---------------------------------------------------------------------------

  @doc """
  Loads and starts a torrent from a URL.

  Passes an empty string as the target (uses rtorrent's default download
  directory). Accepts an optional keyword list:

    * `:label` — sets `d.custom1` via a post-load command
    * `:directory` — sets `d.directory_base` via a post-load command
  """
  @impl Taniwha.CommandsBehaviour
  @spec load_url(String.t(), keyword()) :: :ok | {:error, term()}
  def load_url(url, opts \\ []) do
    Tracer.with_span "taniwha.commands.load_url",
                     %{attributes: %{"command.name": "load_url"}} do
      Logger.info("Command executed", command: "load_url")
      post_cmds = build_post_load_commands(opts)
      @rpc_client.call("load.start", ["", url | post_cmds]) |> ok_on_zero()
    end
  end

  @doc """
  Loads and starts a torrent from raw binary data (e.g. an uploaded `.torrent`
  file).

  Passes an empty string as the target (uses rtorrent's default download
  directory). Accepts an optional keyword list:

    * `:label` — sets `d.custom1` via a post-load command
    * `:directory` — sets `d.directory_base` via a post-load command
  """
  @impl Taniwha.CommandsBehaviour
  @spec load_raw(binary(), keyword()) :: :ok | {:error, term()}
  def load_raw(data, opts \\ []) do
    Tracer.with_span "taniwha.commands.load_raw",
                     %{attributes: %{"command.name": "load_raw"}} do
      Logger.info("Command executed", command: "load_raw")
      post_cmds = build_post_load_commands(opts)
      @rpc_client.call("load.raw_start", ["", {:base64, data} | post_cmds]) |> ok_on_zero()
    end
  end

  # ---------------------------------------------------------------------------
  # Label commands
  # ---------------------------------------------------------------------------

  @doc """
  Sets the label for a torrent.

  rtorrent stores labels in the `d.custom1` field — the de facto standard
  established by ruTorrent. Labels set here will be visible in ruTorrent and
  vice versa.

  **Note:** Labels are stored as plain strings in the post-load command syntax
  `d.custom1.set=<label>`. Labels containing `=` or `,` may not round-trip
  correctly through that syntax — avoid those characters when setting labels
  at load time.
  """
  @impl Taniwha.CommandsBehaviour
  @spec set_label(String.t(), String.t()) :: :ok | {:error, term()}
  def set_label(hash, label) do
    Tracer.with_span "taniwha.commands.set_label",
                     %{attributes: %{"command.name": "set_label", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "set_label", torrent_hash: hash)
      @rpc_client.call("d.custom1.set", [hash, label]) |> ok_on_zero()
    end
  end

  @doc """
  Removes the label from a torrent by setting `d.custom1` to an empty string.
  """
  @impl Taniwha.CommandsBehaviour
  @spec remove_label(String.t()) :: :ok | {:error, term()}
  def remove_label(hash) do
    Tracer.with_span "taniwha.commands.remove_label",
                     %{attributes: %{"command.name": "remove_label", "torrent.hash": hash}} do
      Logger.info("Command executed", command: "remove_label", torrent_hash: hash)
      @rpc_client.call("d.custom1.set", [hash, ""]) |> ok_on_zero()
    end
  end

  @doc """
  Renames a label across all torrents that currently carry `old_name`.

  Reads the ETS cache to find affected torrents, then calls `d.custom1.set`
  on each one. Returns `{:ok, count}` where `count` is the number of torrents
  updated. If any individual RPC call fails, returns
  `{:error, {ok_count, fail_count}}`.

  **Note:** This may issue many RPC calls (one per affected torrent). Callers
  should be prepared for partial failures and the associated inconsistency.
  """
  @impl Taniwha.CommandsBehaviour
  @spec rename_label(String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, {non_neg_integer(), non_neg_integer()}}
  def rename_label(old_name, new_name) do
    affected = Store.get_all_torrents() |> Enum.filter(&(&1.label == old_name))
    results = Enum.map(affected, fn t -> set_label(t.hash, new_name) end)
    ok_count = Enum.count(results, &(&1 == :ok))
    fail_count = length(results) - ok_count

    if fail_count == 0 do
      {:ok, ok_count}
    else
      {:error, {ok_count, fail_count}}
    end
  end

  @doc """
  Returns a sorted list of unique labels currently assigned to any torrent.

  Derived from the ETS cache — no RPC call is made. Returns `[]` when no
  torrents have labels.
  """
  @impl Taniwha.CommandsBehaviour
  @spec get_all_labels() :: [String.t()]
  def get_all_labels do
    Store.get_all_torrents()
    |> Enum.map(& &1.label)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
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

  @doc """
  Returns the rtorrent process ID.

  Used by the health check endpoint to verify rtorrent connectivity. Returns
  `{:ok, pid}` when rtorrent responds, or `{:error, reason}` when unreachable.
  """
  @impl Taniwha.CommandsBehaviour
  @spec system_pid() :: {:ok, term()} | {:error, term()}
  def system_pid do
    Tracer.with_span "taniwha.commands.system_pid",
                     %{attributes: %{"command.name": "system_pid"}} do
      @rpc_client.call("system.pid", [])
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec build_post_load_commands(keyword()) :: [String.t()]
  defp build_post_load_commands(opts) do
    []
    |> maybe_add_label_cmd(Keyword.get(opts, :label))
    |> maybe_add_directory_cmd(Keyword.get(opts, :directory))
  end

  @spec maybe_add_label_cmd([String.t()], String.t() | nil) :: [String.t()]
  defp maybe_add_label_cmd(cmds, nil), do: cmds
  defp maybe_add_label_cmd(cmds, label), do: cmds ++ ["d.custom1.set=#{label}"]

  @spec maybe_add_directory_cmd([String.t()], String.t() | nil) :: [String.t()]
  defp maybe_add_directory_cmd(cmds, nil), do: cmds
  defp maybe_add_directory_cmd(cmds, dir), do: cmds ++ ["d.directory_base.set=#{dir}"]

  @spec run_lifecycle(String.t(), String.t()) :: :ok | {:error, term()}
  defp run_lifecycle(method, hash) do
    @rpc_client.call(method, [hash]) |> ok_on_zero()
  end

  @spec fetch_base_path(String.t()) :: {:ok, String.t()} | {:error, :no_base_path | term()}
  defp fetch_base_path(hash) do
    case @rpc_client.call("d.base_path", [hash]) do
      {:ok, ""} -> {:error, :no_base_path}
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
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
