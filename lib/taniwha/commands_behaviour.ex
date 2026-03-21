defmodule Taniwha.CommandsBehaviour do
  @moduledoc """
  Behaviour for the `Taniwha.Commands` module.

  Defines the contract that `Taniwha.Commands` implements and that Mox-based
  test doubles must satisfy, enabling compile-time injection of the commands
  module into `Taniwha.State.Poller`.
  """

  alias Taniwha.Torrent

  @callback get_all_torrents(String.t()) :: {:ok, [Torrent.t()]} | {:error, term()}
end
