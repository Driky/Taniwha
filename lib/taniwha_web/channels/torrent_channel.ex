defmodule TaniwhaWeb.TorrentChannel do
  @moduledoc """
  Phoenix Channel for real-time torrent data.

  Clients join either `"torrents:list"` (all torrents) or
  `"torrents:{hash}"` (a single torrent). On join the channel subscribes to
  the matching PubSub topic and returns an ETS snapshot so the client starts
  with fresh state and receives incremental diffs thereafter.

  ## Client → Server events

    * `"start"` – start a torrent (`%{"hash" => hash}`)
    * `"stop"` – stop a torrent (`%{"hash" => hash}`)
    * `"remove"` – erase a torrent from rtorrent (`%{"hash" => hash}`)
    * `"set_file_priority"` – set file priority
      (`%{"hash" => hash, "index" => index, "priority" => priority}`)

  ## Server → Client events

    * `"diffs"` – list of changes to the torrent list (`%{diffs: [...]}`)
    * `"updated"` – single torrent updated (`%{torrent: %{...}}`)
  """

  use TaniwhaWeb, :channel

  alias Taniwha.State.Store
  alias TaniwhaWeb.API.TorrentJSON

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  # ---------------------------------------------------------------------------
  # Join handlers
  # ---------------------------------------------------------------------------

  @doc """
  Join handler for `"torrents:list"` and `"torrents:{hash}"` topics.

  - `"torrents:list"` — subscribes to PubSub and returns the full snapshot.
  - `"torrents:{hash}"` — subscribes to the per-torrent PubSub topic and
    returns the torrent snapshot, or `{:error, %{reason: "torrent_not_found"}}`.
  """
  @impl true
  def join("torrents:list", _payload, socket) do
    :ok = Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:list")
    torrents = Enum.map(Store.get_all_torrents(), &TorrentJSON.torrent/1)
    {:ok, %{torrents: torrents}, socket}
  end

  def join("torrents:" <> hash, _payload, socket) do
    case Store.get_torrent(hash) do
      {:ok, torrent} ->
        :ok = Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:#{hash}")
        {:ok, %{torrent: TorrentJSON.torrent(torrent)}, socket}

      {:error, :not_found} ->
        {:error, %{reason: "torrent_not_found"}}
    end
  end

  # ---------------------------------------------------------------------------
  # Command handlers
  # ---------------------------------------------------------------------------

  @doc """
  Handles torrent lifecycle commands: `start`, `stop`, `remove`,
  `set_file_priority`. Each delegates to `@commands` and replies `:ok` or
  `{:error, %{reason: reason}}`.
  """
  @impl true
  def handle_in("start", %{"hash" => hash}, socket),
    do: do_reply(@commands.start(hash), socket)

  def handle_in("stop", %{"hash" => hash}, socket),
    do: do_reply(@commands.stop(hash), socket)

  def handle_in("remove", %{"hash" => hash}, socket),
    do: do_reply(@commands.erase(hash), socket)

  def handle_in(
        "set_file_priority",
        %{"hash" => hash, "index" => index, "priority" => priority},
        socket
      ),
      do: do_reply(@commands.set_file_priority(hash, index, priority), socket)

  # ---------------------------------------------------------------------------
  # PubSub handle_info
  # ---------------------------------------------------------------------------

  @doc """
  Forwards PubSub broadcasts to the connected client.

  - `{:torrent_diffs, diffs}` → pushes `"diffs"` event with serialized diff list
  - `{:torrent_updated, torrent}` → pushes `"updated"` event with serialized torrent
  """
  @impl true
  def handle_info({:torrent_diffs, diffs}, socket) do
    push(socket, "diffs", %{diffs: serialize_diffs(diffs)})
    {:noreply, socket}
  end

  def handle_info({:torrent_updated, torrent}, socket) do
    push(socket, "updated", %{torrent: TorrentJSON.torrent(torrent)})
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec do_reply(:ok | {:error, term()}, Phoenix.Socket.t()) ::
          {:reply, :ok | {:error, map()}, Phoenix.Socket.t()}
  defp do_reply(:ok, socket), do: {:reply, :ok, socket}

  defp do_reply({:error, reason}, socket),
    do: {:reply, {:error, %{reason: inspect(reason)}}, socket}

  @spec serialize_diffs(list()) :: [map()]
  defp serialize_diffs(diffs) do
    Enum.map(diffs, fn
      {:added, torrent} -> %{"type" => "added", "data" => TorrentJSON.torrent(torrent)}
      {:updated, torrent} -> %{"type" => "updated", "data" => TorrentJSON.torrent(torrent)}
      {:removed, hash} -> %{"type" => "removed", "data" => %{"hash" => hash}}
    end)
  end
end
