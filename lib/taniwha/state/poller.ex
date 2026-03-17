defmodule Taniwha.State.Poller do
  @moduledoc "Periodic diff engine for polling rtorrent state. Stub — implemented in Task 3.4."

  use GenServer

  def init(args), do: {:ok, args}
end
