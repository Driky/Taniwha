defmodule Taniwha.SCGI.Connection do
  @moduledoc "Behaviour for SCGI socket connections. Supports Unix and TCP."

  @type transport_config ::
          {:unix, path :: String.t()}
          | {:tcp, host :: String.t(), port :: non_neg_integer()}

  @callback connect(transport_config()) :: {:ok, port()} | {:error, term()}
  @callback send_request(port(), binary()) :: :ok | {:error, term()}
  @callback receive_response(port(), timeout()) :: {:ok, binary()} | {:error, term()}
  @callback close(port()) :: :ok
end
