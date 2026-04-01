defmodule TaniwhaWeb.UserSocket do
  @moduledoc """
  WebSocket entry point.

  Verifies the JWT token supplied in connection params before accepting the
  socket. On success, assigns `:current_user` with the token subject.
  """

  use Phoenix.Socket

  channel "torrents:*", TaniwhaWeb.TorrentChannel
  channel "throttle:settings", TaniwhaWeb.ThrottleChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Taniwha.Auth.verify_token(token) do
      {:ok, user_id} -> {:ok, assign(socket, :current_user, user_id)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user}"
end
