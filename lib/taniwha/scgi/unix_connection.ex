defmodule Taniwha.SCGI.UnixConnection do
  @moduledoc """
  SCGI connection over a Unix domain socket.

  Connects to rtorrent via a local socket file (e.g. `/var/run/rtorrent.sock`).
  Each call to `connect/1` opens a new socket; the caller is responsible for
  closing it with `close/1` when done.
  """

  @behaviour Taniwha.SCGI.Connection

  alias Taniwha.SCGI.Socket

  @doc """
  Opens a connection to the Unix domain socket at `path`.

  Returns `{:ok, socket}` on success, or `{:error, reason}` if the connection
  fails (e.g. `:enoent` when the socket file does not exist, `:eacces` for
  permission errors).
  """
  @spec connect(Taniwha.SCGI.Connection.transport_config()) ::
          {:ok, port()} | {:error, term()}
  @impl Taniwha.SCGI.Connection
  def connect({:unix, path}) do
    :gen_tcp.connect({:local, path}, 0, [:binary, packet: :raw, active: false])
  end

  @doc "Sends `data` over `socket`. Delegates to `Taniwha.SCGI.Socket.send_request/2`."
  @spec send_request(port(), binary()) :: :ok | {:error, term()}
  @impl Taniwha.SCGI.Connection
  defdelegate send_request(socket, data), to: Socket

  @doc "Receives the full response from `socket`. Delegates to `Taniwha.SCGI.Socket.receive_response/2`."
  @spec receive_response(port(), timeout()) :: {:ok, binary()} | {:error, term()}
  @impl Taniwha.SCGI.Connection
  defdelegate receive_response(socket, timeout), to: Socket

  @doc "Closes `socket`. Delegates to `Taniwha.SCGI.Socket.close/1`."
  @spec close(port()) :: :ok
  @impl Taniwha.SCGI.Connection
  defdelegate close(socket), to: Socket
end
