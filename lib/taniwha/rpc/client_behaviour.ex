defmodule Taniwha.RPC.ClientBehaviour do
  @moduledoc """
  Behaviour for the Taniwha RPC client.

  Defines the contract that `Taniwha.RPC.Client` implements and test doubles
  (Mox mocks) must satisfy, enabling compile-time injection of the client
  module in `Taniwha.Commands`.
  """

  @callback call(String.t(), [term()]) :: {:ok, term()} | {:error, term()}
  @callback multicall([{String.t(), [term()]}]) :: {:ok, [term()]} | {:error, term()}
end
