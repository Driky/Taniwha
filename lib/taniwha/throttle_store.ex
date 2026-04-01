defmodule Taniwha.ThrottleStore do
  @moduledoc """
  GenServer that owns the `:taniwha_throttle` ETS table and persists bandwidth
  settings to disk.

  ## Responsibilities

  - Stores the current download/upload speed limits and user-defined presets.
  - Applies saved limits back to rtorrent on startup (so limits survive restarts).
  - Persists settings atomically to a JSON file (tmp → rename) for durability across
    container restarts and Docker volume remounts.
  - Broadcasts PubSub messages so connected LiveViews update in real time.

  ## ETS fast path

  `get_download_limit/0`, `get_upload_limit/0`, and `get_presets/0` read directly
  from the `:taniwha_throttle` ETS table without going through the GenServer mailbox,
  keeping them suitable for use in LiveView render callbacks.

  ## Configuration

  The JSON file path defaults to `priv/throttle_settings.json` and can be overridden
  at runtime via the `TANIWHA_THROTTLE_PATH` environment variable (see `config/runtime.exs`).
  In tests, pass `file_path:` and `ets_table:` opts to `start_link/1` to isolate
  instances from the globally running store.

  ## Concurrency

  All writes are serialised through the GenServer mailbox (last-write-wins). Reads
  bypass the mailbox via ETS, which is `:public` with `read_concurrency: true`.
  """

  use GenServer

  require Logger

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  @default_table :taniwha_throttle

  @default_presets [
    %{value: 512, unit: :kib_s, label: "512 KiB/s"},
    %{value: 1, unit: :mib_s, label: "1 MiB/s"},
    %{value: 2, unit: :mib_s, label: "2 MiB/s"},
    %{value: 5, unit: :mib_s, label: "5 MiB/s"},
    %{value: 10, unit: :mib_s, label: "10 MiB/s"}
  ]

  @type unit() :: :kib_s | :mib_s
  @type preset() :: %{value: pos_integer(), unit: unit(), label: String.t()}

  @type state() :: %{file_path: String.t(), table: atom()}

  # ── Pure helpers ──────────────────────────────────────────────────────────

  @doc "Converts a preset map to bytes per second."
  @spec preset_to_bytes(preset()) :: non_neg_integer()
  def preset_to_bytes(%{value: v, unit: :mib_s}), do: v * 1_048_576
  def preset_to_bytes(%{value: v, unit: :kib_s}), do: v * 1_024

  @doc """
  Returns a human-readable string for a byte-per-second value.

      iex> Taniwha.ThrottleStore.bytes_to_display(0)
      "Unlimited"

      iex> Taniwha.ThrottleStore.bytes_to_display(5_242_880)
      "5 MiB/s"

      iex> Taniwha.ThrottleStore.bytes_to_display(524_288)
      "512 KiB/s"
  """
  @spec bytes_to_display(non_neg_integer()) :: String.t()
  def bytes_to_display(0), do: "Unlimited"

  def bytes_to_display(bytes) when bytes >= 1_048_576 do
    mib = bytes / 1_048_576
    "#{format_number(mib)} MiB/s"
  end

  def bytes_to_display(bytes) do
    kib = bytes / 1_024
    "#{format_number(kib)} KiB/s"
  end

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the ThrottleStore.

  Accepted options:
    * `name:` — GenServer registration name. Defaults to `__MODULE__`. Pass `false`
      to skip registration (useful in tests).
    * `file_path:` — path for the JSON persistence file. Defaults to
      `Application.get_env(:taniwha, :throttle_settings_path)`.
    * `ets_table:` — ETS table name. Defaults to `:taniwha_throttle`. Override in
      tests to avoid conflicting with the globally running instance.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc "Returns the current download speed limit from ETS. `0` means unlimited."
  @spec get_download_limit() :: non_neg_integer()
  def get_download_limit do
    :ets.lookup_element(@default_table, :download_limit, 2)
  end

  @doc "Returns the current upload speed limit from ETS. `0` means unlimited."
  @spec get_upload_limit() :: non_neg_integer()
  def get_upload_limit do
    :ets.lookup_element(@default_table, :upload_limit, 2)
  end

  @doc "Returns the current list of speed presets from ETS."
  @spec get_presets() :: [preset()]
  def get_presets do
    :ets.lookup_element(@default_table, :presets, 2)
  end

  @doc """
  Sets the global download speed limit in bytes/s.

  Applies the limit to rtorrent, then updates ETS and persists to file.
  Broadcasts `{:throttle_updated, %{download_limit: bytes, upload_limit: bytes}}`
  on the `"throttle:settings"` PubSub topic. Returns `{:error, reason}` without
  modifying state if the RPC call fails.
  """
  @spec set_download_limit(non_neg_integer(), GenServer.server()) :: :ok | {:error, term()}
  def set_download_limit(bytes, server \\ __MODULE__) do
    GenServer.call(server, {:set_download_limit, bytes})
  end

  @doc """
  Sets the global upload speed limit in bytes/s.

  Same semantics as `set_download_limit/2`.
  """
  @spec set_upload_limit(non_neg_integer(), GenServer.server()) :: :ok | {:error, term()}
  def set_upload_limit(bytes, server \\ __MODULE__) do
    GenServer.call(server, {:set_upload_limit, bytes})
  end

  @doc """
  Replaces the preset list.

  Validates that all presets have a valid unit (`:kib_s` or `:mib_s`), a positive
  integer value, and no two presets that resolve to the same byte count. Returns
  `{:error, :invalid_unit | :invalid_value | :duplicate_preset}` on validation
  failure.
  """
  @spec set_presets([preset()], GenServer.server()) :: :ok | {:error, term()}
  def set_presets(presets, server \\ __MODULE__) do
    GenServer.call(server, {:set_presets, presets})
  end

  @doc """
  Resets ETS to defaults without touching rtorrent or the file on disk.

  Intended for use in tests to restore a known state between test cases.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    file_path =
      Keyword.get(
        opts,
        :file_path,
        Application.get_env(:taniwha, :throttle_settings_path, "priv/throttle_settings.json")
      )

    table = Keyword.get(opts, :ets_table, @default_table)

    :ets.new(table, [:set, :named_table, :public, {:read_concurrency, true}])

    {dl, ul, presets, loaded?} = load_from_file(file_path)
    populate_ets(table, dl, ul, presets)

    unless loaded? do
      persist_to_file(%{file_path: file_path, table: table}, dl, ul, presets)
    end

    apply_limits_on_startup(dl, ul)

    {:ok, %{file_path: file_path, table: table}}
  end

  @impl true
  def handle_call({:set_download_limit, bytes}, _from, state) do
    case @commands.set_download_limit(bytes) do
      :ok ->
        :ets.insert(state.table, {:download_limit, bytes})
        {dl, ul, presets} = read_ets(state.table)
        persist_to_file(state, dl, ul, presets)
        broadcast_throttle_update(dl, ul)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_upload_limit, bytes}, _from, state) do
    case @commands.set_upload_limit(bytes) do
      :ok ->
        :ets.insert(state.table, {:upload_limit, bytes})
        {dl, ul, presets} = read_ets(state.table)
        persist_to_file(state, dl, ul, presets)
        broadcast_throttle_update(dl, ul)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_presets, presets}, _from, state) do
    case validate_presets(presets) do
      :ok ->
        :ets.insert(state.table, {:presets, presets})
        {dl, ul, _} = read_ets(state.table)
        persist_to_file(state, dl, ul, presets)
        broadcast_presets_update(presets)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    populate_ets(state.table, 0, 0, @default_presets)
    {:reply, :ok, state}
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  @spec populate_ets(atom(), non_neg_integer(), non_neg_integer(), [preset()]) :: :ok
  defp populate_ets(table, dl, ul, presets) do
    :ets.insert(table, {:download_limit, dl})
    :ets.insert(table, {:upload_limit, ul})
    :ets.insert(table, {:presets, presets})
    :ok
  end

  @spec read_ets(atom()) :: {non_neg_integer(), non_neg_integer(), [preset()]}
  defp read_ets(table) do
    dl = :ets.lookup_element(table, :download_limit, 2)
    ul = :ets.lookup_element(table, :upload_limit, 2)
    presets = :ets.lookup_element(table, :presets, 2)
    {dl, ul, presets}
  end

  # Applies saved limits to rtorrent on startup.
  # Wrapped in try/rescue to handle Mox.UnexpectedCallError in tests (no
  # expectations set at boot time) and unexpected rtorrent unavailability.
  @spec apply_limits_on_startup(non_neg_integer(), non_neg_integer()) :: :ok
  defp apply_limits_on_startup(download_limit, upload_limit) do
    try do
      case @commands.set_download_limit(download_limit) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("ThrottleStore: startup apply download limit failed",
            reason: inspect(reason)
          )
      end

      case @commands.set_upload_limit(upload_limit) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("ThrottleStore: startup apply upload limit failed",
            reason: inspect(reason)
          )
      end
    rescue
      e ->
        Logger.warning("ThrottleStore: startup apply limits raised", error: inspect(e))
    end

    :ok
  end

  @spec load_from_file(String.t()) ::
          {non_neg_integer(), non_neg_integer(), [preset()], boolean()}
  defp load_from_file(path) do
    if File.exists?(path) do
      with {:ok, json} <- File.read(path),
           {:ok, parsed} <- Jason.decode(json),
           {:ok, data} <- validate_json(parsed) do
        presets =
          Enum.map(data["presets"], fn p ->
            %{
              value: p["value"],
              unit: String.to_existing_atom(p["unit"]),
              label: p["label"]
            }
          end)

        {data["download_limit"], data["upload_limit"], presets, true}
      else
        _ ->
          Logger.warning("ThrottleStore: could not parse #{path}, using defaults")
          {0, 0, @default_presets, false}
      end
    else
      {0, 0, @default_presets, false}
    end
  end

  @spec validate_json(map()) :: {:ok, map()} | {:error, :invalid_format}
  defp validate_json(
         %{
           "version" => 1,
           "download_limit" => dl,
           "upload_limit" => ul,
           "presets" => presets
         } = data
       )
       when is_integer(dl) and dl >= 0 and is_integer(ul) and ul >= 0 and is_list(presets) do
    {:ok, data}
  end

  defp validate_json(_), do: {:error, :invalid_format}

  @spec persist_to_file(state(), non_neg_integer(), non_neg_integer(), [preset()]) :: :ok
  defp persist_to_file(state, dl, ul, presets) do
    presets_json =
      Enum.map(presets, fn p ->
        %{"value" => p.value, "unit" => Atom.to_string(p.unit), "label" => p.label}
      end)

    json =
      Jason.encode!(%{
        "version" => 1,
        "download_limit" => dl,
        "upload_limit" => ul,
        "presets" => presets_json
      })

    tmp = state.file_path <> ".tmp"

    case File.write(tmp, json) do
      :ok ->
        case File.rename(tmp, state.file_path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("ThrottleStore: rename failed", reason: inspect(reason))
        end

      {:error, reason} ->
        Logger.warning("ThrottleStore: write failed", reason: inspect(reason))
    end

    :ok
  end

  @spec broadcast_throttle_update(non_neg_integer(), non_neg_integer()) :: :ok
  defp broadcast_throttle_update(dl, ul) do
    Phoenix.PubSub.broadcast(
      Taniwha.PubSub,
      "throttle:settings",
      {:throttle_updated, %{download_limit: dl, upload_limit: ul}}
    )
  end

  @spec broadcast_presets_update([preset()]) :: :ok
  defp broadcast_presets_update(presets) do
    Phoenix.PubSub.broadcast(
      Taniwha.PubSub,
      "throttle:settings",
      {:presets_updated, presets}
    )
  end

  @spec validate_presets([map()]) ::
          :ok | {:error, :invalid_unit | :invalid_value | :duplicate_preset}
  defp validate_presets(presets) do
    valid_units = [:kib_s, :mib_s]

    with :ok <- check_all(presets, fn p -> p[:unit] in valid_units end, :invalid_unit),
         :ok <-
           check_all(
             presets,
             fn p -> is_integer(p[:value]) and p[:value] > 0 end,
             :invalid_value
           ),
         bytes_list = Enum.map(presets, &preset_to_bytes/1),
         :ok <-
           if(Enum.uniq(bytes_list) == bytes_list,
             do: :ok,
             else: {:error, :duplicate_preset}
           ) do
      :ok
    end
  end

  @spec check_all([map()], (map() -> boolean()), atom()) :: :ok | {:error, atom()}
  defp check_all(list, pred, error) do
    if Enum.all?(list, pred), do: :ok, else: {:error, error}
  end

  @spec format_number(float()) :: integer() | float()
  defp format_number(n) do
    rounded = Float.round(n, 1)
    if rounded == trunc(rounded) * 1.0, do: trunc(rounded), else: rounded
  end
end
