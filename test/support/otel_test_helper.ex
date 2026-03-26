defmodule Taniwha.OtelTestHelper do
  @moduledoc """
  Shared helpers for OpenTelemetry span assertions in ExUnit tests.

  ## Usage

      use TaniwhaWeb.ConnCase, async: false
      import Taniwha.OtelTestHelper

      setup :setup_otel_exporter

      test "my span is emitted" do
        MyModule.do_work()
        span = assert_span("taniwha.my.span", attributes: [{"my.attr", "value"}])
        assert span_status(span) == :ok
      end

  Tests that use this helper **must** set `async: false` because
  `setup_otel_exporter/1` mutates the global `:otel_simple_processor` exporter
  state.
  """

  import ExUnit.Assertions

  require Record

  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @span_fields)

  @doc """
  ExUnit setup callback that routes exported spans to the test process.

  Call via `setup :setup_otel_exporter` or include in a `setup` block:

      setup :setup_otel_exporter

  Registers an `on_exit` hook that restores the exporter so spans emitted
  after the test do not leak into other modules.
  """
  @spec setup_otel_exporter(map()) :: :ok
  def setup_otel_exporter(_context \\ %{}) do
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

    ExUnit.Callbacks.on_exit(fn ->
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    end)

    :ok
  end

  @doc """
  Asserts that a span with the given `name` is received by this test process.

  Consumes spans from the process mailbox until it finds one whose name
  matches, discarding spans with different names. This is necessary because
  child spans (which end before their parents) arrive in the mailbox before
  their parent spans.

  Options:
  - `:attributes` — list of `{key, value}` pairs that must all be present.
    Keys may be strings or atoms; values are compared with `==`.
  - `:timeout` — milliseconds to wait for the span (default: `2_000`).

  Returns the raw span record so callers can make additional assertions.

      span = assert_span("taniwha.rpc.call", attributes: [{"rpc.method", "d.name"}])
      assert span_status(span) == :ok
  """
  @spec assert_span(String.t(), keyword()) :: term()
  def assert_span(name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2_000)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_span(name, opts, deadline)
  end

  defp do_assert_span(name, opts, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    assert_receive {:span, span_record}, remaining

    if span(span_record, :name) == name do
      for {key, expected} <- Keyword.get(opts, :attributes, []) do
        actual = span_attribute(span_record, key)

        assert actual == expected,
               "Expected span attribute #{inspect(key)} to be #{inspect(expected)}, " <>
                 "got #{inspect(actual)}"
      end

      span_record
    else
      # Not the span we're looking for — keep consuming
      do_assert_span(name, opts, deadline)
    end
  end

  @doc """
  Returns the value of a span attribute by key.

  Accepts both string and atom keys. Returns `nil` if the attribute is absent.

      span_attribute(span_record, "rpc.method")   #=> "d.name"
      span_attribute(span_record, :"rpc.method")  #=> "d.name"
  """
  @spec span_attribute(term(), String.t() | atom()) :: term()
  def span_attribute(span_record, key) when is_binary(key),
    do: span_attribute(span_record, String.to_atom(key))

  def span_attribute(span_record, key) when is_atom(key) do
    span_record
    |> span(:attributes)
    |> :otel_attributes.map()
    |> Map.get(key)
  end

  @doc """
  Returns the status of a span record as an atom (`:ok`, `:error`, or `:unset`).
  """
  @spec span_status(term()) :: :ok | :error | :unset
  def span_status(span_record) do
    case span(span_record, :status) do
      {:status, :ok, _} -> :ok
      {:status, :error, _} -> :error
      _ -> :unset
    end
  end

  @doc "Returns the span_id of a span record."
  @spec span_id(term()) :: integer()
  def span_id(span_record), do: span(span_record, :span_id)

  @doc "Returns the parent_span_id of a span record."
  @spec parent_span_id(term()) :: integer()
  def parent_span_id(span_record), do: span(span_record, :parent_span_id)
end
