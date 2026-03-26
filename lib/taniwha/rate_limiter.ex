defmodule Taniwha.RateLimiter do
  @moduledoc """
  ETS-backed sliding-window rate limiter.

  Tracks request counts per bucket within a configurable time window. The
  GenServer serialises all check-and-increment operations to guarantee
  atomicity; reads are never performed outside this process.

  ## Usage

      # Allow 10 requests per 60 seconds from a given IP
      case Taniwha.RateLimiter.check_and_increment({:auth, remote_ip}, 10, 60_000) do
        :ok -> # proceed
        {:error, :rate_limited} -> # reject with 429
      end
  """

  use GenServer

  require Logger

  @table :taniwha_rate_limiter

  @doc "Starts the rate limiter and creates the named ETS table."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Checks whether `bucket` is within `limit` requests per `window_ms` milliseconds
  and, if so, increments the counter.

  Returns `:ok` when the request is allowed, or `{:error, :rate_limited}` when
  the bucket has exceeded the limit for the current window.

  The window resets automatically once `window_ms` milliseconds have elapsed
  since the first request in that window.
  """
  @spec check_and_increment(term(), pos_integer(), pos_integer()) :: :ok | {:error, :rate_limited}
  def check_and_increment(bucket, limit, window_ms) do
    GenServer.call(__MODULE__, {:check_and_increment, bucket, limit, window_ms})
  end

  @doc """
  Deletes all counters from the ETS table.

  Intended for use in tests to reset state between cases. Routes through the
  GenServer to satisfy the `:protected` table access constraint.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ── GenServer callbacks ──────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :protected])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:check_and_increment, bucket, limit, window_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)
    result = do_check_and_increment(bucket, limit, window_ms, now)
    {:reply, result, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  @spec do_check_and_increment(term(), pos_integer(), pos_integer(), integer()) ::
          :ok | {:error, :rate_limited}
  defp do_check_and_increment(bucket, limit, window_ms, now) do
    case :ets.lookup(@table, bucket) do
      [] ->
        :ets.insert(@table, {bucket, 1, now})
        :ok

      [{^bucket, count, window_start}] ->
        if now - window_start >= window_ms do
          :ets.insert(@table, {bucket, 1, now})
          :ok
        else
          if count >= limit do
            {:error, :rate_limited}
          else
            :ets.update_counter(@table, bucket, {2, 1})
            :ok
          end
        end
    end
  end
end
