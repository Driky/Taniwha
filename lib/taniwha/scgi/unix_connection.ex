defmodule Taniwha.SCGI.UnixConnection do
  @moduledoc """
  SCGI connection over a Unix domain socket.

  Connects to rtorrent via a local socket file (e.g. `/var/run/rtorrent.sock`).
  Each call to `connect/1` opens a new socket; the caller is responsible for
  closing it with `close/1` when done.
  """

  @behaviour Taniwha.SCGI.Connection

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

  @doc """
  Sends `data` over `socket`.

  Returns `:ok` on success, `{:error, reason}` on failure (e.g. `:closed`).
  """
  @spec send_request(port(), binary()) :: :ok | {:error, term()}
  @impl Taniwha.SCGI.Connection
  def send_request(socket, data) do
    :gen_tcp.send(socket, data)
  end

  @doc """
  Receives the full response from `socket`, waiting up to `timeout` milliseconds
  between chunks.

  rtorrent closes the connection after sending its response, so this function
  accumulates data until it receives `{:error, :closed}`, then returns the
  accumulated binary. Each individual `recv` call is bounded by `timeout`.
  """
  @spec receive_response(port(), timeout()) :: {:ok, binary()} | {:error, term()}
  @impl Taniwha.SCGI.Connection
  def receive_response(socket, timeout) do
    receive_all(socket, timeout, "")
  end

  @doc """
  Closes `socket`.

  Always returns `:ok`.
  """
  @spec close(port()) :: :ok
  @impl Taniwha.SCGI.Connection
  def close(socket) do
    :gen_tcp.close(socket)
    :ok
  end

  @spec receive_all(port(), timeout(), binary()) :: {:ok, binary()} | {:error, term()}
  defp receive_all(socket, timeout, acc) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} -> receive_all(socket, timeout, acc <> data)
      {:error, :closed} -> {:ok, acc}
      {:error, reason} -> {:error, reason}
    end
  end
end
