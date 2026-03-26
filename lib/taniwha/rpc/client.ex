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

  ## Observability

  Each `call/2` and `multicall/1` produces a `taniwha.rpc.call` /
  `taniwha.rpc.multicall` OpenTelemetry span. The caller's OTel context is
  captured before the GenServer dispatch so that spans are correctly nested
  under the caller's parent span. See `docs/observability.md` for the full
  span and attribute catalogue.
  """

  use GenServer

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @behaviour Taniwha.RPC.ClientBehaviour

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
  @impl true
  @spec call(String.t(), [term()]) :: {:ok, term()} | {:error, term()}
  def call(method, params) when is_binary(method) and is_list(params) do
    ctx = :otel_ctx.get_current()
    GenServer.call(__MODULE__, {:call, method, params, ctx}, :infinity)
  end

  @doc """
  Issues a `system.multicall` request and returns the list of per-call results.

  Each element in the returned list is a single-element array (rtorrent wraps
  every multicall result in `[value]`).
  """
  @impl true
  @spec multicall([{String.t(), [term()]}]) :: {:ok, [term()]} | {:error, term()}
  def multicall(calls) when is_list(calls) do
    ctx = :otel_ctx.get_current()
    GenServer.call(__MODULE__, {:multicall, calls, ctx}, :infinity)
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
  def handle_call({:call, method, params, ctx}, _from, state) do
    result =
      with_otel_context(ctx, fn ->
        Tracer.with_span "taniwha.rpc.call",
                         %{
                           attributes: %{
                             "rpc.method": method,
                             "rpc.param_count": length(params),
                             "rpc.transport": transport_type(state.transport)
                           }
                         } do
          do_request(XMLRPC.encode_call(method, params), state) |> record_rpc_result()
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:multicall, calls, ctx}, _from, state) do
    result =
      with_otel_context(ctx, fn ->
        Tracer.with_span "taniwha.rpc.multicall",
                         %{
                           attributes: %{
                             "rpc.call_count": length(calls),
                             "rpc.transport": transport_type(state.transport)
                           }
                         } do
          do_request(XMLRPC.encode_multicall(calls), state) |> record_rpc_result()
        end
      end)

    {:reply, result, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec with_otel_context(:otel_ctx.t(), (-> term())) :: term()
  defp with_otel_context(ctx, fun) do
    token = :otel_ctx.attach(ctx)

    try do
      fun.()
    after
      :otel_ctx.detach(token)
    end
  end

  @spec record_rpc_result({:ok, term()} | {:error, term()}) :: {:ok, term()} | {:error, term()}
  defp record_rpc_result({:ok, response} = ok) do
    Tracer.set_attribute(:"rpc.response_size", :erlang.external_size(response))
    ok
  end

  defp record_rpc_result({:error, reason} = error) do
    Tracer.set_status(:error, inspect(reason))
    Tracer.set_attribute(:"rpc.error_reason", inspect(reason))
    error
  end

  @spec transport_type(transport_config()) :: String.t()
  defp transport_type({type, _}), do: to_string(type)
  defp transport_type({type, _, _}), do: to_string(type)

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
