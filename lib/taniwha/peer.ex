defmodule Taniwha.Peer do
  @moduledoc """
  Struct representing a peer connected to a torrent.
  """

  @type t :: %__MODULE__{
          address: String.t(),
          port: non_neg_integer(),
          client_version: String.t(),
          down_rate: non_neg_integer(),
          up_rate: non_neg_integer(),
          completed_percent: float()
        }

  defstruct address: "",
            port: 0,
            client_version: "",
            down_rate: 0,
            up_rate: 0,
            completed_percent: 0.0

  @doc """
  Returns the peer address formatted as `"IP:port"` for display.
  """
  @spec address_port(t()) :: String.t()
  def address_port(%__MODULE__{address: addr, port: port}), do: "#{addr}:#{port}"
end
