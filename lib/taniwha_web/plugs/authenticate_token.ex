defmodule TaniwhaWeb.Plugs.AuthenticateToken do
  @moduledoc "Plug for JWT token authentication. Stub — implemented in Task 2.1."

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts), do: conn
end
