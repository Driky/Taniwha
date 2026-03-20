defmodule Taniwha.SCGI.TcpConnection do
  @moduledoc """
  SCGI connection over a TCP socket.

  Connects to rtorrent via a TCP host/port pair (e.g. `{"localhost", 5000}`).
  Each call to `connect/1` opens a new socket; the caller is responsible for
  closing it with `close/1` when done.
  """

  @behaviour Taniwha.SCGI.Connection

  alias Taniwha.SCGI.Socket

  @doc """
  Opens a TCP connection to `host` on `port`.

  Returns `{:ok, socket}` on success, or `{:error, reason}` if the connection
  fails (e.g. `:econnrefused`, `:timeout`, `:nxdomain`).
  """
  @spec connect(Taniwha.SCGI.Connection.transport_config()) ::
          {:ok, port()} | {:error, term()}
  @impl Taniwha.SCGI.Connection
  def connect({:tcp, host, port}) do
    :gen_tcp.connect(String.to_charlist(host), port, [:binary, packet: :raw, active: false])
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
