defmodule Taniwha.State.Store do
  @moduledoc "ETS-backed torrent state cache. Stub — implemented in Task 3.3."

  use GenServer

  def init(args), do: {:ok, args}
end
