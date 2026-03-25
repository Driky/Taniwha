defmodule TaniwhaWeb.OtelTest do
  @moduledoc """
  Verifies the OpenTelemetry integration.

  Two levels of coverage:

  1. **Pipeline test** – manually creates a span and asserts the configured
     exporter receives it.  Verifies that the OTel SDK, the simple processor,
     and `:otel_exporter_pid` are all wired up correctly.

  2. **Router-dispatch test** – makes a real Phoenix request inside a `with_span`
     block and asserts that `OpentelemetryPhoenix` added the `http.route`
     attribute to the current span.  This works in `ConnCase` (no real TCP
     socket needed) because the Phoenix router-dispatch telemetry event fires
     in-process.

  Note: Full Bandit → HTTP → trace round-trip testing (including
  `http.request.method` and `http.response.status_code` from
  `OpentelemetryBandit`) requires a real TCP connection and is covered by
  manual smoke-testing with the stdout exporter.

  These tests must run `async: false` because they mutate the global
  `:otel_simple_processor` exporter state.
  """
  use TaniwhaWeb.ConnCase, async: false

  import Mox

  require OpenTelemetry.Tracer
  require Record

  # Pull in the span record so we can read span fields in assertions.
  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp :span, @span_fields

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # Route all exported spans to this test process for the duration of the test.
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    :ok
  end

  describe "OTel pipeline" do
    test "a manually created span is exported to the configured exporter" do
      OpenTelemetry.Tracer.with_span "taniwha.test.pipeline" do
        OpenTelemetry.Tracer.set_attributes([{:"test.key", "hello"}])
      end

      assert_receive {:span, span}, 2_000
      assert span(span, :name) == "taniwha.test.pipeline"
      assert span_attribute(span, "test.key") == "hello"
    end
  end

  describe "Phoenix router-dispatch auto-instrumentation" do
    test "GET /api/v1/torrents adds http.route to the current span", %{conn: conn} do
      OpenTelemetry.Tracer.with_span "test_request" do
        conn |> with_auth() |> get("/api/v1/torrents")
        # OpentelemetryPhoenix's router_dispatch handler runs synchronously
        # in this process and calls Tracer.set_attributes on the current span.
      end

      assert_receive {:span, span}, 2_000
      # The router dispatch handler updates the span name to "METHOD ROUTE"
      assert span(span, :name) == "GET /api/v1/torrents"
      assert span_attribute(span, "http.route") == "/api/v1/torrents"
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Attribute keys in OTel spans are atoms (e.g. :"http.route").
  # Accept both string and atom keys for convenience.
  defp span_attribute(span_record, key) when is_binary(key),
    do: span_attribute(span_record, String.to_atom(key))

  defp span_attribute(span_record, key) when is_atom(key) do
    span_record
    |> span(:attributes)
    |> :otel_attributes.map()
    |> Map.get(key)
  end
end
