defmodule TaniwhaWeb.UserSocket do
  @moduledoc "WebSocket entry point. Stub — implemented in Task 4.1."
  use Phoenix.Socket

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
