defmodule TaniwhaWeb.API.TorrentJSON do
  @moduledoc """
  JSON rendering for torrent responses.

  Also serves as the canonical torrent serializer for both REST and WebSocket
  (Channel) layers. `TorrentChannel` delegates to `torrent/1` to ensure a
  consistent API surface.
  """

  alias Taniwha.Torrent

  @doc "Renders a list of torrents."
  @spec index(map()) :: map()
  def index(%{torrents: torrents}), do: %{torrents: Enum.map(torrents, &torrent/1)}

  @doc "Renders a single torrent."
  @spec show(map()) :: map()
  def show(%{torrent: t}), do: %{torrent: torrent(t)}

  @doc "Renders the result of a torrent creation request."
  @spec create(map()) :: map()
  def create(%{status: status}), do: %{status: status}

  @doc "Serializes a `Torrent` struct to a plain map suitable for JSON encoding."
  @spec torrent(Torrent.t()) :: map()
  def torrent(%Torrent{} = t) do
    %{
      "hash" => t.hash,
      "name" => t.name,
      "size" => t.size,
      "completedBytes" => t.completed_bytes,
      "uploadRate" => t.upload_rate,
      "downloadRate" => t.download_rate,
      "ratio" => t.ratio,
      "state" => Atom.to_string(t.state),
      "isActive" => t.is_active,
      "complete" => t.complete,
      "isHashChecking" => t.is_hash_checking,
      "peersConnected" => t.peers_connected,
      "startedAt" => maybe_iso8601(t.started_at),
      "finishedAt" => maybe_iso8601(t.finished_at),
      "basePath" => t.base_path,
      "progress" => Torrent.progress(t),
      "status" => Atom.to_string(Torrent.status(t))
    }
  end

  @spec maybe_iso8601(DateTime.t() | nil) :: String.t() | nil
  defp maybe_iso8601(nil), do: nil
  defp maybe_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
