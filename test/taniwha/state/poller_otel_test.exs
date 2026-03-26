defmodule Taniwha.State.PollerOtelTest do
  @moduledoc """
  Tests for OpenTelemetry span instrumentation on `Taniwha.State.Poller`.

  Verifies that each poll cycle produces a correctly named and attributed
  `taniwha.poller.cycle` span, and that error paths set the span status to
  error.

  Must run `async: false` because we mutate the global `:otel_simple_processor`
  exporter state.
  """
  use ExUnit.Case, async: false

  import Mox
  import Taniwha.OtelTestHelper

  alias Taniwha.State.{Poller, Store}
  alias Taniwha.Torrent

  setup :verify_on_exit!
  setup :setup_otel_exporter

  setup do
    Store.clear()
    :ok
  end

  defp build_torrent(hash, overrides \\ []) do
    struct!(Torrent, Keyword.merge([hash: hash, name: "Torrent #{hash}"], overrides))
  end

  defp start_poller(interval \\ 60_000) do
    {:ok, pid} = GenServer.start_link(Poller, poll_interval: interval)
    Mox.allow(Taniwha.MockCommands, self(), pid)
    pid
  end

  defp poll_and_wait(pid) do
    send(pid, :poll)
    :sys.get_state(pid)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Successful poll cycle spans
  # ---------------------------------------------------------------------------

  describe "successful poll cycle" do
    test "creates a taniwha.poller.cycle span" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, []} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert_span("taniwha.poller.cycle")
    end

    test "sets poller.torrent_count attribute" do
      t1 = build_torrent("h1")
      t2 = build_torrent("h2")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [t1, t2]} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert_span("taniwha.poller.cycle", attributes: [{"poller.torrent_count", 2}])
    end

    test "sets poller.diff_count attribute" do
      t1 = build_torrent("h1")

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [t1]} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert_span("taniwha.poller.cycle", attributes: [{"poller.diff_count", 1}])
    end

    test "sets poller.interval_ms attribute" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, []} end)

      pid = start_poller(12_345)
      poll_and_wait(pid)

      assert_span("taniwha.poller.cycle", attributes: [{"poller.interval_ms", 12_345}])
    end

    test "diff_count is 0 when no changes occurred" do
      t1 = build_torrent("h1")
      Store.put_torrent(t1)

      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:ok, [t1]} end)

      pid = start_poller()
      poll_and_wait(pid)

      span = assert_span("taniwha.poller.cycle")
      assert span_attribute(span, "poller.diff_count") == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Failed poll cycle spans
  # ---------------------------------------------------------------------------

  describe "failed poll cycle" do
    test "creates a taniwha.poller.cycle span on error" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()
      poll_and_wait(pid)

      assert_span("taniwha.poller.cycle")
    end

    test "sets span status to error on fetch failure" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :econnrefused} end)

      pid = start_poller()
      poll_and_wait(pid)

      span = assert_span("taniwha.poller.cycle")
      assert span_status(span) == :error
    end

    test "sets poller.error_reason attribute on failure" do
      Taniwha.MockCommands
      |> expect(:get_all_torrents, fn "" -> {:error, :timeout} end)

      pid = start_poller()
      poll_and_wait(pid)

      span = assert_span("taniwha.poller.cycle")
      assert span_attribute(span, "poller.error_reason") == ":timeout"
    end
  end
end
