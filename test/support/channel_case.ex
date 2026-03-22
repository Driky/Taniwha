defmodule TaniwhaWeb.ChannelCase do
  @moduledoc "ExUnit case template for Phoenix Channel tests."

  use ExUnit.CaseTemplate

  import Mox

  using do
    quote do
      import Phoenix.ChannelTest
      import Mox
      @endpoint TaniwhaWeb.Endpoint
    end
  end

  setup :set_mox_from_context
  setup :verify_on_exit!
end
