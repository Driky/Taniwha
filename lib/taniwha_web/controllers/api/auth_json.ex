defmodule TaniwhaWeb.API.AuthJSON do
  @moduledoc "JSON rendering for auth responses."

  @doc "Renders a successful token response."
  @spec create(map()) :: map()
  def create(%{token: token}), do: %{token: token}
end
