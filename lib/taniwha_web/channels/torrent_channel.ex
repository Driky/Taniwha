defmodule TaniwhaWeb.TorrentChannel do
  @moduledoc "Phoenix Channel for real-time torrent updates. Stub — implemented in Task 4.2."
  use TaniwhaWeb, :channel

  @impl true
  def join(_topic, _payload, socket), do: {:ok, socket}
end
