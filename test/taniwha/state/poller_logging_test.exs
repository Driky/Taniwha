defmodule Taniwha.State.PollerLoggingTest do
  @moduledoc """
  Tests for structured log output from `Taniwha.State.Poller`.

  Verifies that:
  - Failed polls emit a structured warning (not a string-interpolated message)
  - The warning metadata includes error_reason and consecutive_failures
  - Successful polls emit a debug-level log with torrent_count and diff_count
  - `duration_ms` is included in the success log

  Must run `async: false` because :logger handler installation is global.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox
  import Taniwha.LogCapture

  alias Taniwha.State.{Poller, Store}
  alias Taniwha.Torrent

  setup :verify_on_exit!

  setup do
    Store.clear()
    :ok
  end

  defp build_torrent(hash) do
    struct!(Torrent, hash: hash, name: "Torrent #{hash}")
  end

  defp start_poller do
    {:ok, pid} = GenServer.start_link(Poller, poll_interval: 60_000)
    Mox.allow(Taniwha.MockCommands, self(), pid)
    pid
  end

  defp poll_and_wait(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Failed poll — structured warning
  # ---------------------------------------------------------------------------

  describe "failed poll logging" do
    test "emits warning with structured message (not string-interpolated)" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()

      log = capture_log(fn -> poll_and_wait(pid) end)

      assert log =~ "Poll cycle failed"
      refute log =~ "Poller: failed to fetch torrents:"
    end

    test "warning metadata includes error_reason" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :timeout} end)

      pid = start_poller()

      events = capture_log_events([level: :warning], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle failed")
      assert event != nil, "Expected to find 'Poll cycle failed' log event"
      assert log_meta(event, :error_reason) == ":timeout"
    end

    test "warning metadata includes consecutive_failures count" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()

      events = capture_log_events([level: :warning], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle failed")
      assert event != nil
      assert log_meta(event, :consecutive_failures) == 1
    end

    test "consecutive_failures increments on repeated failures" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, 2, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()
      poll_and_wait(pid)

      events = capture_log_events([level: :warning], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle failed")
      assert event != nil
      assert log_meta(event, :consecutive_failures) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Successful poll — debug log
  # ---------------------------------------------------------------------------

  describe "successful poll logging" do
    test "emits debug log with torrent_count" do
      t1 = build_torrent("h1")
      t2 = build_torrent("h2")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [t1, t2]} end)

      pid = start_poller()

      events = capture_log_events([level: :debug], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle completed")
      assert event != nil, "Expected to find 'Poll cycle completed' debug log"
      assert log_meta(event, :torrent_count) == 2
    end

    test "success log includes diff_count" do
      t1 = build_torrent("h1")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [t1]} end)

      pid = start_poller()

      events = capture_log_events([level: :debug], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle completed")
      assert event != nil
      assert log_meta(event, :diff_count) == 1
    end

    test "success log includes duration_ms as a non-negative integer" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, []} end)

      pid = start_poller()

      events = capture_log_events([level: :debug], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle completed")
      assert event != nil
      duration_ms = log_meta(event, :duration_ms)
      assert is_integer(duration_ms)
      assert duration_ms >= 0
    end

    test "success log is at :debug level" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, []} end)

      pid = start_poller()

      events = capture_log_events([level: :debug], fn -> poll_and_wait(pid) end)

      event = find_event(events, "Poll cycle completed")
      assert event != nil
      assert event.level == :debug
    end
  end
end
