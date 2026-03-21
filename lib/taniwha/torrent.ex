defmodule Taniwha.Torrent do
  @moduledoc """
  Struct representing a torrent with helper functions.

  Used by the State layer (poller, store) and eventually the API layer.
  `rpc_fields/0` exposes the ordered list of rtorrent field names so that
  `Taniwha.Commands` can reference it without duplicating the order.
  """

  @enforce_keys [:hash, :name]

  @type t :: %__MODULE__{
          hash: String.t(),
          name: String.t(),
          size: non_neg_integer(),
          completed_bytes: non_neg_integer(),
          upload_rate: non_neg_integer(),
          download_rate: non_neg_integer(),
          ratio: float(),
          state: :started | :stopped,
          is_active: boolean(),
          complete: boolean(),
          is_hash_checking: boolean(),
          peers_connected: non_neg_integer(),
          started_at: DateTime.t() | nil,
          finished_at: DateTime.t() | nil,
          base_path: String.t() | nil,
          files: list() | nil
        }

  defstruct [
    :hash,
    :name,
    size: 0,
    completed_bytes: 0,
    upload_rate: 0,
    download_rate: 0,
    ratio: 0.0,
    state: :stopped,
    is_active: false,
    complete: false,
    is_hash_checking: false,
    peers_connected: 0,
    started_at: nil,
    finished_at: nil,
    base_path: nil,
    files: nil
  ]

  @rpc_fields [
    "d.name",
    "d.size_bytes",
    "d.completed_bytes",
    "d.up.rate",
    "d.down.rate",
    "d.ratio",
    "d.state",
    "d.is_active",
    "d.complete",
    "d.is_hash_checking",
    "d.peers_connected",
    "d.timestamp.started",
    "d.timestamp.finished",
    "d.base_path"
  ]

  @doc """
  Returns the ordered list of rtorrent RPC field names used to build a Torrent
  from a multicall response. `Taniwha.Commands` uses this to avoid hardcoding
  the field order in two places.
  """
  @spec rpc_fields() :: [String.t()]
  def rpc_fields, do: @rpc_fields

  @doc """
  Returns download progress as a float between 0.0 and 1.0.

  Returns `0.0` when `size` is 0 (torrent not yet initialised).
  """
  @spec progress(t()) :: float()
  def progress(%__MODULE__{size: 0}), do: 0.0

  def progress(%__MODULE__{completed_bytes: completed, size: size}) do
    completed / size
  end

  @doc """
  Converts rtorrent's raw ratio integer (ratio × 1000) to a float.

  For example, `1500 → 1.5`.
  """
  @spec ratio_display(non_neg_integer()) :: float()
  def ratio_display(raw), do: raw / 1000

  @doc """
  Returns the semantic status of a torrent based on its state flags.

  Priority order: `:checking` → `:downloading` → `:seeding` → `:paused` →
  `:stopped` → `:unknown`.
  """
  @spec status(t()) :: :checking | :downloading | :seeding | :paused | :stopped | :unknown
  def status(%__MODULE__{is_hash_checking: true}), do: :checking
  def status(%__MODULE__{state: :started, is_active: true, complete: false}), do: :downloading
  def status(%__MODULE__{state: :started, is_active: true, complete: true}), do: :seeding
  def status(%__MODULE__{state: :started, is_active: false}), do: :paused
  def status(%__MODULE__{state: :stopped}), do: :stopped
  def status(%__MODULE__{}), do: :unknown

  @doc """
  Constructs a `Torrent` from a hash string and a flat list of RPC values.

  Values must be in the same order as `rpc_fields/0`. The caller
  (`Taniwha.Commands`) is responsible for unwrapping rtorrent multicall's
  outer `[[value]]` nesting before passing values here.
  """
  @spec from_rpc_values(String.t(), list()) :: t()
  def from_rpc_values(hash, [
        name,
        size,
        completed_bytes,
        up_rate,
        down_rate,
        ratio,
        state,
        is_active,
        complete,
        is_hash_checking,
        peers_connected,
        ts_started,
        ts_finished,
        base_path
      ]) do
    %__MODULE__{
      hash: hash,
      name: name,
      size: size,
      completed_bytes: completed_bytes,
      upload_rate: up_rate,
      download_rate: down_rate,
      ratio: ratio_display(ratio),
      state: decode_state(state),
      is_active: is_active == 1,
      complete: complete == 1,
      is_hash_checking: is_hash_checking == 1,
      peers_connected: peers_connected,
      started_at: decode_timestamp(ts_started),
      finished_at: decode_timestamp(ts_finished),
      base_path: decode_base_path(base_path)
    }
  end

  @spec decode_state(0 | 1) :: :stopped | :started
  defp decode_state(0), do: :stopped
  defp decode_state(1), do: :started

  @spec decode_timestamp(non_neg_integer()) :: DateTime.t() | nil
  defp decode_timestamp(0), do: nil
  defp decode_timestamp(ts), do: DateTime.from_unix!(ts, :second)

  @spec decode_base_path(String.t()) :: String.t() | nil
  defp decode_base_path(""), do: nil
  defp decode_base_path(path), do: path
end
