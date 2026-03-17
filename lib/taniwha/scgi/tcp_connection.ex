defmodule Taniwha.SCGI.TcpConnection do
  @moduledoc "SCGI connection over TCP. Stub — implemented in Task 2.2."

  @behaviour Taniwha.SCGI.Connection

  @impl Taniwha.SCGI.Connection
  def connect(_config), do: {:error, :not_implemented}

  @impl Taniwha.SCGI.Connection
  def send_request(_socket, _data), do: {:error, :not_implemented}

  @impl Taniwha.SCGI.Connection
  def receive_response(_socket, _timeout), do: {:error, :not_implemented}

  @impl Taniwha.SCGI.Connection
  def close(_socket), do: :ok
end
