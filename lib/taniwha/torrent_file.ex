defmodule Taniwha.TorrentFile do
  @moduledoc """
  Struct representing a single file within a torrent, with helper functions.
  """

  @type t :: %__MODULE__{
          path: String.t() | nil,
          size: non_neg_integer(),
          completed_chunks: non_neg_integer(),
          total_chunks: non_neg_integer(),
          priority: non_neg_integer()
        }

  defstruct path: nil,
            size: 0,
            completed_chunks: 0,
            total_chunks: 0,
            priority: 1

  @doc """
  Returns download progress as a float between 0.0 and 1.0.

  Returns `0.0` when the file has no chunks (uninitialized or zero-byte file).
  """
  @spec progress(t()) :: float()
  def progress(%__MODULE__{total_chunks: 0}), do: 0.0

  def progress(%__MODULE__{completed_chunks: completed, total_chunks: total}) do
    completed / total
  end

  @doc """
  Returns an atom label for the given rtorrent priority integer.

  - `0` → `:skip`
  - `1` → `:normal`
  - `2` → `:high`
  """
  @spec priority_label(non_neg_integer()) :: :skip | :normal | :high
  def priority_label(0), do: :skip
  def priority_label(1), do: :normal
  def priority_label(2), do: :high
end
