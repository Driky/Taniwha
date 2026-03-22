defmodule Taniwha.CommandsBehaviour do
  @moduledoc """
  Behaviour for the `Taniwha.Commands` module.

  Defines the contract that `Taniwha.Commands` implements and that Mox-based
  test doubles must satisfy, enabling compile-time injection of the commands
  module into `Taniwha.State.Poller`.
  """

  alias Taniwha.Torrent

  @callback get_all_torrents(String.t()) :: {:ok, [Torrent.t()]} | {:error, term()}
  @callback start(String.t()) :: :ok | {:error, term()}
  @callback stop(String.t()) :: :ok | {:error, term()}
  @callback erase(String.t()) :: :ok | {:error, term()}
  @callback set_file_priority(String.t(), non_neg_integer(), non_neg_integer()) ::
              :ok | {:error, term()}
  @callback load_url(String.t()) :: :ok | {:error, term()}
  @callback load_raw(binary()) :: :ok | {:error, term()}
end
