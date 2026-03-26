defmodule Taniwha.CommandsBehaviour do
  @moduledoc """
  Behaviour for the `Taniwha.Commands` module.

  Defines the contract that `Taniwha.Commands` implements and that Mox-based
  test doubles must satisfy, enabling compile-time injection of the commands
  module into `Taniwha.State.Poller`.
  """

  alias Taniwha.Peer
  alias Taniwha.Torrent
  alias Taniwha.TorrentFile
  alias Taniwha.Tracker

  @callback get_all_torrents(String.t()) :: {:ok, [Torrent.t()]} | {:error, term()}
  @callback start(String.t()) :: :ok | {:error, term()}
  @callback stop(String.t()) :: :ok | {:error, term()}
  @callback pause(String.t()) :: :ok | {:error, term()}
  @callback erase(String.t()) :: :ok | {:error, term()}
  @callback list_files(String.t()) :: {:ok, [TorrentFile.t()]} | {:error, term()}
  @callback set_file_priority(String.t(), non_neg_integer(), non_neg_integer()) ::
              :ok | {:error, term()}
  @callback list_peers(String.t()) :: {:ok, [Peer.t()]} | {:error, term()}
  @callback list_trackers(String.t()) :: {:ok, [Tracker.t()]} | {:error, term()}
  @callback load_url(String.t()) :: :ok | {:error, term()}
  @callback load_raw(binary()) :: :ok | {:error, term()}
  @callback system_pid() :: {:ok, term()} | {:error, term()}
end
