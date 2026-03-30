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
    * `"set_label"` – set the label for a torrent
      (`%{"hash" => hash, "label" => label}`)

  ## Server → Client events

    * `"diffs"` – list of changes to the torrent list (`%{diffs: [...]}`)
    * `"updated"` – single torrent updated (`%{torrent: %{...}}`)

  ## Observability

  Each `handle_in` callback wraps its work in a `taniwha.channel.{event}`
  OpenTelemetry span with `channel.topic`, `channel.event`, and `torrent.hash`
  attributes. Error paths set the span status to `:error`. The WebSocket
  connections gauge in `Taniwha.Telemetry.Metrics` is updated on join and
  terminate. See `docs/observability.md` for the full catalogue.
  """

  use TaniwhaWeb, :channel

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Taniwha.{State.Store, Validator}
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
    Taniwha.Telemetry.Metrics.inc_websocket_connections()
    torrents = Enum.map(Store.get_all_torrents(), &TorrentJSON.torrent/1)
    {:ok, %{torrents: torrents}, assign(socket, :last_command_at, :never)}
  end

  def join("torrents:" <> hash, _payload, socket) do
    case Store.get_torrent(hash) do
      {:ok, torrent} ->
        :ok = Phoenix.PubSub.subscribe(Taniwha.PubSub, "torrents:#{hash}")
        Taniwha.Telemetry.Metrics.inc_websocket_connections()
        {:ok, %{torrent: TorrentJSON.torrent(torrent)}, assign(socket, :last_command_at, :never)}

      {:error, :not_found} ->
        {:error, %{reason: "torrent_not_found"}}
    end
  end

  # ---------------------------------------------------------------------------
  # Terminate
  # ---------------------------------------------------------------------------

  @impl true
  def terminate(_reason, _socket) do
    Taniwha.Telemetry.Metrics.dec_websocket_connections()
    :ok
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
  def handle_in("start", %{"hash" => hash}, socket) do
    with {:ok, socket} <- check_and_update_rate_limit(socket),
         :ok <- Validator.validate_hash(hash) do
      with_command_span("start", hash, socket, fn -> @commands.start(hash) end)
    else
      {:error, :rate_limited} -> {:reply, {:error, %{reason: "rate_limited"}}, socket}
      {:error, :invalid_hash} -> {:reply, {:error, %{reason: "invalid hash"}}, socket}
    end
  end

  def handle_in("stop", %{"hash" => hash}, socket) do
    with {:ok, socket} <- check_and_update_rate_limit(socket),
         :ok <- Validator.validate_hash(hash) do
      with_command_span("stop", hash, socket, fn -> @commands.stop(hash) end)
    else
      {:error, :rate_limited} -> {:reply, {:error, %{reason: "rate_limited"}}, socket}
      {:error, :invalid_hash} -> {:reply, {:error, %{reason: "invalid hash"}}, socket}
    end
  end

  def handle_in("remove", %{"hash" => hash}, socket) do
    with {:ok, socket} <- check_and_update_rate_limit(socket),
         :ok <- Validator.validate_hash(hash) do
      with_command_span("remove", hash, socket, fn -> @commands.erase(hash) end)
    else
      {:error, :rate_limited} -> {:reply, {:error, %{reason: "rate_limited"}}, socket}
      {:error, :invalid_hash} -> {:reply, {:error, %{reason: "invalid hash"}}, socket}
    end
  end

  def handle_in("set_label", %{"hash" => hash, "label" => label}, socket) do
    with {:ok, socket} <- check_and_update_rate_limit(socket),
         :ok <- Validator.validate_hash(hash) do
      with_command_span("set_label", hash, socket, fn -> @commands.set_label(hash, label) end)
    else
      {:error, :rate_limited} -> {:reply, {:error, %{reason: "rate_limited"}}, socket}
      {:error, :invalid_hash} -> {:reply, {:error, %{reason: "invalid hash"}}, socket}
    end
  end

  def handle_in(
        "set_file_priority",
        %{"hash" => hash, "index" => index, "priority" => priority},
        socket
      ) do
    with {:ok, socket} <- check_and_update_rate_limit(socket),
         :ok <- Validator.validate_hash(hash),
         :ok <- Validator.validate_priority(priority) do
      with_command_span("set_file_priority", hash, socket, fn ->
        @commands.set_file_priority(hash, index, priority)
      end)
    else
      {:error, :rate_limited} -> {:reply, {:error, %{reason: "rate_limited"}}, socket}
      {:error, :invalid_hash} -> {:reply, {:error, %{reason: "invalid hash"}}, socket}
      {:error, :invalid_priority} -> {:reply, {:error, %{reason: "invalid priority"}}, socket}
    end
  end

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

  # ---------------------------------------------------------------------------
  # Rate limiting
  # ---------------------------------------------------------------------------

  @doc false
  @spec check_and_update_rate_limit(Phoenix.Socket.t()) ::
          {:ok, Phoenix.Socket.t()} | {:error, :rate_limited}
  defp check_and_update_rate_limit(socket) do
    now = System.monotonic_time(:millisecond)

    # `:never` is the initial sentinel — first command after join is always allowed.
    # We can't use 0 because BEAM's monotonic clock can start at a large negative
    # value, making `now - 0` negative (i.e., less than 500) and incorrectly
    # blocking the very first command.
    case socket.assigns.last_command_at do
      :never ->
        {:ok, assign(socket, :last_command_at, now)}

      last when now - last < 500 ->
        {:error, :rate_limited}

      _ ->
        {:ok, assign(socket, :last_command_at, now)}
    end
  end

  @spec with_command_span(String.t(), String.t(), Phoenix.Socket.t(), (-> :ok | {:error, term()})) ::
          {:reply, :ok | {:error, map()}, Phoenix.Socket.t()}
  defp with_command_span(event, hash, socket, command_fn) do
    result =
      Tracer.with_span "taniwha.channel.#{event}",
                       %{
                         attributes: %{
                           "channel.topic": socket.topic,
                           "channel.event": event,
                           "torrent.hash": hash
                         }
                       } do
        Logger.info("Channel command received",
          channel_topic: socket.topic,
          event: event,
          torrent_hash: hash
        )

        case command_fn.() do
          :ok -> :ok
          {:error, _reason} = err -> set_error_status(err)
        end
      end

    do_reply(result, socket)
  end

  @spec set_error_status({:error, term()}) :: {:error, term()}
  defp set_error_status({:error, reason} = error) do
    Tracer.set_status(:error, inspect(reason))
    error
  end

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
