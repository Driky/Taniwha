defmodule Taniwha.LabelStore do
  @moduledoc """
  GenServer that stores label colour metadata and persists it to disk.

  Labels in rtorrent are plain strings stored in `d.custom1`. Colour is
  Taniwha-side metadata. This store maps label names to a colour triplet:

      {dot_color, bg_color, text_color}

  where each value is a hex string (e.g. `"#ec4899"`).

  ## Colour assignment

  When a label is first accessed via `auto_assign/2`, the next unused colour
  from the 6-entry palette is assigned. After the palette is exhausted, the
  assignment wraps around. Users can override the colour with `set_color/4`.

  ## Persistence

  Data is stored as plaintext JSON at `<data_dir>/labels.json`. Writes are
  atomic (write to `.tmp` then rename). Labels are not sensitive — no
  encryption is required.

  ## Configuration

  Pass `data_dir:` and optionally `name:` to `start_link/1`. In production,
  `data_dir` is set from the `TANIWHA_DATA_DIR` env var via `Application`.

  ## Examples

      iex> {dot, _bg, _text} = LabelStore.auto_assign("Movies")
      iex> String.starts_with?(dot, "#")
      true
  """

  use GenServer

  require Logger

  @palette [
    {"#ec4899", "#fce7f3", "#be185d"},
    {"#6366f1", "#e0e7ff", "#4338ca"},
    {"#a855f7", "#f3e8ff", "#7e22ce"},
    {"#22c55e", "#dcfce7", "#15803d"},
    {"#3b82f6", "#dbeafe", "#1d4ed8"},
    {"#f59e0b", "#fef3c7", "#b45309"}
  ]

  @type colour_triplet() :: {String.t(), String.t(), String.t()}

  @type state() :: %{
          data_dir: String.t(),
          labels: %{String.t() => colour_triplet()},
          next_index: non_neg_integer()
        }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the label store.

  Pass `name: false` to skip global registration (useful in tests).
  Defaults to registering as `Taniwha.LabelStore`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Returns the 6 dot colours in the fixed palette, in order.

  Useful for tests and for rendering the colour picker.
  """
  @spec palette_dot_colours() :: [String.t()]
  def palette_dot_colours, do: Enum.map(@palette, &elem(&1, 0))

  @doc """
  Returns the full palette as `{dot, bg, text}` triplets.
  """
  @spec palette() :: [colour_triplet()]
  def palette, do: @palette

  @doc """
  Returns the stored colour triplet for `label`, or auto-assigns the next
  palette colour if the label is not yet known.

  The result is stored so repeated calls return the same value.
  """
  @spec auto_assign(String.t(), GenServer.server()) :: colour_triplet()
  def auto_assign(label, server \\ __MODULE__) do
    GenServer.call(server, {:auto_assign, label})
  end

  @doc """
  Sets an explicit colour triplet for `label`.

  Returns `:ok`. Any previously auto-assigned colour is replaced.
  """
  @spec set_color(String.t(), String.t(), String.t(), String.t(), GenServer.server()) :: :ok
  def set_color(label, dot, bg, text, server \\ __MODULE__) do
    GenServer.call(server, {:set_color, label, dot, bg, text})
  end

  @doc """
  Removes the colour entry for `label`.

  Returns `:ok` even if the label was not present.
  """
  @spec delete(String.t(), GenServer.server()) :: :ok
  def delete(label, server \\ __MODULE__) do
    GenServer.call(server, {:delete, label})
  end

  @doc """
  Returns a map of all stored labels and their colour triplets.
  """
  @spec get_all(GenServer.server()) :: %{String.t() => colour_triplet()}
  def get_all(server \\ __MODULE__) do
    GenServer.call(server, :get_all)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    data_dir =
      Keyword.get(opts, :data_dir, Application.get_env(:taniwha, :data_dir, "/data/taniwha"))

    File.mkdir_p!(data_dir)

    state = %{data_dir: data_dir, labels: %{}, next_index: 0}
    state = load_from_disk(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:auto_assign, label}, _from, state) do
    case Map.get(state.labels, label) do
      nil ->
        triplet = Enum.at(@palette, rem(state.next_index, length(@palette)))

        new_state = %{
          state
          | labels: Map.put(state.labels, label, triplet),
            next_index: state.next_index + 1
        }

        persist(new_state)
        {:reply, triplet, new_state}

      triplet ->
        {:reply, triplet, state}
    end
  end

  def handle_call({:set_color, label, dot, bg, text}, _from, state) do
    new_state = %{state | labels: Map.put(state.labels, label, {dot, bg, text})}
    persist(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call({:delete, label}, _from, state) do
    new_state = %{state | labels: Map.delete(state.labels, label)}
    persist(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:get_all, _from, state) do
    {:reply, state.labels, state}
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  @spec persist(state()) :: :ok
  defp persist(state) do
    serialized =
      Map.new(state.labels, fn {name, {dot, bg, text}} ->
        {name, %{dot: dot, bg: bg, text: text}}
      end)

    payload = Jason.encode!(%{version: 1, next_index: state.next_index, labels: serialized})
    tmp = labels_file(state) <> ".tmp"
    File.write!(tmp, payload)
    File.rename!(tmp, labels_file(state))
    :ok
  end

  @spec load_from_disk(state()) :: state()
  defp load_from_disk(state) do
    path = labels_file(state)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, %{"version" => 1, "labels" => raw_labels, "next_index" => next_index}} ->
              labels =
                Map.new(raw_labels, fn {name, %{"dot" => dot, "bg" => bg, "text" => text}} ->
                  {name, {dot, bg, text}}
                end)

              %{state | labels: labels, next_index: next_index}

            _ ->
              Logger.warning("LabelStore: could not parse #{path}, starting fresh.")
              state
          end

        {:error, reason} ->
          Logger.warning(
            "LabelStore: could not read #{path}: #{inspect(reason)}, starting fresh."
          )

          state
      end
    else
      state
    end
  end

  @spec labels_file(state()) :: String.t()
  defp labels_file(state), do: Path.join(state.data_dir, "labels.json")
end
