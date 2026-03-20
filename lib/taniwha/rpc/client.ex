defmodule Taniwha.RPC.Client do
  @moduledoc """
  GenServer RPC client for rtorrent.

  Serialises XML-RPC calls over the configured SCGI transport (Unix socket or
  TCP). Each call opens a new connection, sends the framed request, reads the
  response, and closes the connection — matching rtorrent's one-connection-per-
  call model.

  Configuration (read once at start-up):

      config :taniwha,
        scgi_connection: Taniwha.SCGI.UnixConnection,
        scgi_transport: {:unix, "/var/run/rtorrent.sock"},
        scgi_timeout: 5_000
  """

  use GenServer

  alias Taniwha.SCGI.Protocol
  alias Taniwha.XMLRPC

  @type transport_config ::
          {:unix, String.t()}
          | {:tcp, String.t(), non_neg_integer()}

  @type state :: %{
          connection: module(),
          transport: transport_config(),
          timeout: non_neg_integer()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Starts the RPC client as a named GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Issues a single XML-RPC method call and returns the decoded result.

  Uses `:infinity` timeout on the GenServer call; the socket-level timeout
  (`:scgi_timeout`) governs how long to wait for rtorrent to respond.
  """
  @spec call(String.t(), [term()]) :: {:ok, term()} | {:error, term()}
  def call(method, params) when is_binary(method) and is_list(params) do
    GenServer.call(__MODULE__, {:call, method, params}, :infinity)
  end

  @doc """
  Issues a `system.multicall` request and returns the list of per-call results.

  Each element in the returned list is a single-element array (rtorrent wraps
  every multicall result in `[value]`).
  """
  @spec multicall([{String.t(), [term()]}]) :: {:ok, [term()]} | {:error, term()}
  def multicall(calls) when is_list(calls) do
    GenServer.call(__MODULE__, {:multicall, calls}, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    connection = Application.fetch_env!(:taniwha, :scgi_connection)
    transport = Application.fetch_env!(:taniwha, :scgi_transport)
    timeout = Application.get_env(:taniwha, :scgi_timeout, 5_000)

    {:ok, %{connection: connection, transport: transport, timeout: timeout}}
  end

  @impl true
  def handle_call({:call, method, params}, _from, state) do
    xml = XMLRPC.encode_call(method, params)
    result = do_request(xml, state)
    {:reply, result, state}
  end

  def handle_call({:multicall, calls}, _from, state) do
    xml = XMLRPC.encode_multicall(calls)
    result = do_request(xml, state)
    {:reply, result, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec do_request(binary(), state()) :: {:ok, term()} | {:error, term()}
  defp do_request(xml, %{connection: conn, transport: transport, timeout: timeout}) do
    frame = Protocol.encode(xml)

    with {:ok, socket} <- conn.connect(transport),
         :ok <- send_and_close_on_error(conn, socket, frame),
         {:ok, raw} <- recv_and_close(conn, socket, timeout),
         {:ok, xml_body} <- Protocol.decode_response(raw) do
      XMLRPC.decode_response(xml_body)
    end
  end

  @spec send_and_close_on_error(module(), term(), binary()) :: :ok | {:error, term()}
  defp send_and_close_on_error(conn, socket, frame) do
    case conn.send_request(socket, frame) do
      :ok ->
        :ok

      {:error, reason} ->
        conn.close(socket)
        {:error, reason}
    end
  end

  @spec recv_and_close(module(), term(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  defp recv_and_close(conn, socket, timeout) do
    result = conn.receive_response(socket, timeout)
    conn.close(socket)
    result
  end
end
