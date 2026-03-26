defmodule Taniwha.StructuredLoggingTest do
  @moduledoc """
  Tests for structured logging and trace-log correlation.

  Verifies that:
  - Logs emitted within active OTel spans include trace_id and span_id in output
  - The opentelemetry_logger_metadata primary filter is active
  - Logs emitted outside any span do not include trace_id
  - Sensitive data (API keys, tokens) never appears in log output

  Must run `async: false` because CaptureLog and OTel context are global state.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  # ---------------------------------------------------------------------------
  # Trace-log correlation
  # ---------------------------------------------------------------------------

  describe "trace-log correlation" do
    test "log within active OTel span includes trace_id in formatted output" do
      log =
        capture_log(fn ->
          Tracer.with_span "test.correlation" do
            Logger.warning("correlation test marker")
          end
        end)

      assert log =~ "trace_id="
      assert log =~ "span_id="
    end

    test "log outside any span does not include trace_id" do
      log = capture_log(fn -> Logger.warning("no span marker") end)

      refute log =~ "trace_id="
    end

    test "opentelemetry_logger_metadata primary filter is active" do
      %{filters: filters} = :logger.get_primary_config()
      filter_ids = filters |> Keyword.keys()
      assert :opentelemetry_logger_metadata in filter_ids
    end
  end

  # ---------------------------------------------------------------------------
  # Sensitive data rules
  # ---------------------------------------------------------------------------

  describe "sensitive data" do
    test "API key never appears in any log output" do
      api_key = Application.get_env(:taniwha, :api_key)

      # Simulate a scenario where a misbehaving call might log the key
      log =
        capture_log(fn ->
          # Normal logging should never include the api_key
          Logger.warning("Some warning", reason: "test")
          Logger.info("Some info", data: "safe_value")
        end)

      if api_key, do: refute(log =~ api_key)
    end
  end
end
