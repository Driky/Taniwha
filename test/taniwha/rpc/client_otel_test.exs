defmodule Taniwha.RPC.ClientOtelTest do
  @moduledoc """
  Tests for OpenTelemetry span instrumentation on `Taniwha.RPC.Client`.

  Verifies that `call/2` and `multicall/1` produce correctly named and
  attributed spans, propagate parent context from the caller's process into
  the GenServer process, and set error status + record exceptions on failure.

  Must run `async: false` because:
  - The RPC.Client is a globally-named GenServer.
  - We mutate the global `:otel_simple_processor` exporter state.
  """
  use ExUnit.Case, async: false

  import Mox
  import Taniwha.OtelTestHelper

  require OpenTelemetry.Tracer

  alias Taniwha.RPC.Client
  alias Taniwha.SCGI.MockConnection
  alias Taniwha.Test.Fixtures

  setup :verify_on_exit!
  setup :setup_otel_exporter

  setup do
    Mox.allow(MockConnection, self(), Process.whereis(Client))
    :ok
  end

  defp scgi_response(xml),
    do: "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n" <> xml

  defp stub_successful_call(xml) do
    response = scgi_response(xml)

    MockConnection
    |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
    |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
    |> expect(:receive_response, fn :fake_socket, _timeout -> {:ok, response} end)
    |> expect(:close, fn :fake_socket -> :ok end)
  end

  defp stub_connect_failure do
    MockConnection
    |> expect(:connect, fn {:unix, _} -> {:error, :enoent} end)
  end

  # ---------------------------------------------------------------------------
  # call/2 spans
  # ---------------------------------------------------------------------------

  describe "call/2 OTel spans" do
    test "creates a taniwha.rpc.call span" do
      stub_successful_call(Fixtures.torrent_name_xml())
      Client.call("d.name", ["abc123"])

      assert_span("taniwha.rpc.call")
    end

    test "sets rpc.method attribute" do
      stub_successful_call(Fixtures.torrent_name_xml())
      Client.call("d.name", ["abc123"])

      assert_span("taniwha.rpc.call", attributes: [{"rpc.method", "d.name"}])
    end

    test "sets rpc.param_count attribute" do
      stub_successful_call(Fixtures.torrent_name_xml())
      Client.call("d.name", ["abc123"])

      assert_span("taniwha.rpc.call", attributes: [{"rpc.param_count", 1}])
    end

    test "sets rpc.transport attribute to unix" do
      stub_successful_call(Fixtures.torrent_name_xml())
      Client.call("d.name", ["abc123"])

      assert_span("taniwha.rpc.call", attributes: [{"rpc.transport", "unix"}])
    end

    test "sets rpc.response_size on success" do
      stub_successful_call(Fixtures.torrent_name_xml())
      Client.call("d.name", ["abc123"])

      span = assert_span("taniwha.rpc.call")
      assert is_integer(span_attribute(span, "rpc.response_size"))
      assert span_attribute(span, "rpc.response_size") > 0
    end

    test "sets error status on connect failure" do
      stub_connect_failure()
      Client.call("d.name", ["abc123"])

      span = assert_span("taniwha.rpc.call")
      assert span_status(span) == :error
    end

    test "sets rpc.error_reason attribute on failure" do
      stub_connect_failure()
      Client.call("d.name", ["abc123"])

      span = assert_span("taniwha.rpc.call")
      assert span_attribute(span, "rpc.error_reason") == ":connection_failed"
    end

    test "span is nested under parent when parent context is active" do
      stub_successful_call(Fixtures.torrent_name_xml())

      OpenTelemetry.Tracer.with_span "test.parent" do
        Client.call("d.name", ["abc123"])
      end

      # Two spans are received: rpc.call (child) and test.parent (outer)
      rpc_span = assert_span("taniwha.rpc.call")
      parent_span = assert_span("test.parent")

      # The rpc span's parent_span_id must equal the parent span's span_id
      assert parent_span_id(rpc_span) == span_id(parent_span)
    end
  end

  # ---------------------------------------------------------------------------
  # multicall/1 spans
  # ---------------------------------------------------------------------------

  describe "multicall/1 OTel spans" do
    test "creates a taniwha.rpc.multicall span" do
      stub_successful_call(Fixtures.multicall_xml())

      calls = [{"d.name", ["hash"]}, {"d.size_bytes", ["hash"]}]
      Client.multicall(calls)

      assert_span("taniwha.rpc.multicall")
    end

    test "sets rpc.call_count attribute" do
      stub_successful_call(Fixtures.multicall_xml())

      calls = [
        {"d.name", ["hash"]},
        {"d.size_bytes", ["hash"]},
        {"d.completed_bytes", ["hash"]},
        {"d.complete", ["hash"]},
        {"d.hashing", ["hash"]},
        {"d.timestamp.started", ["hash"]},
        {"d.directory", ["hash"]}
      ]

      Client.multicall(calls)

      assert_span("taniwha.rpc.multicall", attributes: [{"rpc.call_count", 7}])
    end

    test "sets rpc.transport attribute" do
      stub_successful_call(Fixtures.multicall_xml())

      Client.multicall([{"d.name", ["hash"]}])

      assert_span("taniwha.rpc.multicall", attributes: [{"rpc.transport", "unix"}])
    end

    test "sets error status on failure" do
      stub_connect_failure()
      Client.multicall([{"d.name", ["hash"]}])

      span = assert_span("taniwha.rpc.multicall")
      assert span_status(span) == :error
    end
  end
end
