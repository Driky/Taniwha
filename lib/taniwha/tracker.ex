defmodule Taniwha.Tracker do
  @moduledoc """
  Struct representing a tracker associated with a torrent.
  """

  @type t :: %__MODULE__{
          url: String.t(),
          is_enabled: boolean(),
          scrape_complete: non_neg_integer(),
          scrape_incomplete: non_neg_integer(),
          normal_interval: non_neg_integer()
        }

  defstruct url: "",
            is_enabled: true,
            scrape_complete: 0,
            scrape_incomplete: 0,
            normal_interval: 0

  @doc """
  Returns `:enabled` or `:disabled` based on the tracker's `is_enabled` field.
  """
  @spec status(t()) :: :enabled | :disabled
  def status(%__MODULE__{is_enabled: true}), do: :enabled
  def status(%__MODULE__{is_enabled: false}), do: :disabled
end
