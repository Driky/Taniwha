defmodule Taniwha.SCGI.Socket do
  @moduledoc """
  Shared `:gen_tcp` I/O helpers for SCGI connections.

  Both `Taniwha.SCGI.UnixConnection` and `Taniwha.SCGI.TcpConnection` delegate
  their `send_request/2`, `receive_response/2`, and `close/1` callbacks here.
  Only `connect/1` differs between the two transports; all socket I/O after
  the connection is established is identical.
  """

  @doc """
  Sends `data` over `socket`.

  Returns `:ok` on success, `{:error, reason}` on failure (e.g. `:closed`).
  """
  @spec send_request(port(), binary()) :: :ok | {:error, term()}
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
  def receive_response(socket, timeout) do
    receive_all(socket, timeout, "")
  end

  @doc """
  Closes `socket`.

  Always returns `:ok`.
  """
  @spec close(port()) :: :ok
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
