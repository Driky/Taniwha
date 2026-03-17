defmodule TaniwhaWeb.ChannelCase do
  @moduledoc "ExUnit case template for Phoenix Channel tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      @endpoint TaniwhaWeb.Endpoint
    end
  end
end
