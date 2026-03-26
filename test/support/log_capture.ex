defmodule Taniwha.LogCapture do
  @moduledoc """
  Test support module for capturing raw Erlang `:logger` events.

  Unlike `ExUnit.CaptureLog` (which captures formatted strings),
  `LogCapture` gives access to the raw `meta` map — allowing assertions
  on structured metadata keys like `error_reason` and `consecutive_failures`
  that are set via `Logger.warning("msg", key: value)`.

  ## Usage

      import Taniwha.LogCapture

      test "log includes error_reason in metadata" do
        events = capture_log_events([level: :warning], fn ->
          Taniwha.State.Poller.do_something_that_fails()
        end)

        event = find_event(events, "Poll cycle failed")
        assert log_meta(event, :error_reason) == ":econnrefused"
      end
  """

  @handler_id :taniwha_test_log_capture

  @doc """
  Captures raw `:logger` events emitted during `fun`.

  Options:
  - `:level` — minimum level to capture (default `:warning`)
  """
  @spec capture_log_events(keyword(), (-> any())) :: [map()]
  def capture_log_events(opts \\ [], fun) do
    level = Keyword.get(opts, :level, :warning)
    test_pid = self()

    # Temporarily lower the primary logger level so messages reach our handler.
    # (The global test level is :warning; debug/info messages are dropped before
    # any handler unless we lower the primary level here.)
    original_primary = :logger.get_primary_config().level
    needs_lower = compare_levels(level, original_primary) == :lt
    if needs_lower, do: :logger.set_primary_config(:level, level)

    :logger.add_handler(@handler_id, __MODULE__, %{
      level: level,
      test_pid: test_pid
    })

    try do
      fun.()
    after
      :logger.remove_handler(@handler_id)
      if needs_lower, do: :logger.set_primary_config(:level, original_primary)
    end

    collect_events()
  end

  @doc "Returns the value of a metadata key from a captured log event."
  @spec log_meta(map(), atom()) :: term()
  def log_meta(%{meta: meta}, key), do: Map.get(meta, key)

  @doc """
  Returns the first event whose message contains `text`, or `nil`.
  """
  @spec find_event([map()], String.t()) :: map() | nil
  def find_event(events, text) do
    Enum.find(events, fn event ->
      event |> format_msg() |> String.contains?(text)
    end)
  end

  # ── Erlang :logger handler callbacks ──────────────────────────────────────

  @doc false
  def adding_handler(config), do: {:ok, config}

  @doc false
  def removing_handler(_config), do: :ok

  @doc false
  def log(event, %{test_pid: pid}) do
    send(pid, {:log_event, event})
    :ok
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  # Returns :lt if level_a is less severe than level_b (e.g. :debug < :warning).
  @levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]
  defp compare_levels(a, b) do
    ia = Enum.find_index(@levels, &(&1 == a)) || 0
    ib = Enum.find_index(@levels, &(&1 == b)) || 0

    cond do
      ia < ib -> :lt
      ia > ib -> :gt
      true -> :eq
    end
  end

  defp collect_events(acc \\ []) do
    receive do
      {:log_event, event} -> collect_events([event | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp format_msg(%{msg: {:string, chardata}}), do: IO.chardata_to_string(chardata)
  defp format_msg(%{msg: {:report, report}}), do: inspect(report)

  defp format_msg(%{msg: {:format, fmt, args}}),
    do: :io_lib.format(fmt, args) |> IO.chardata_to_string()

  defp format_msg(_), do: ""
end
