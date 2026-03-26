defmodule Taniwha.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Taniwha.RateLimiter

  setup do
    RateLimiter.clear()
    :ok
  end

  # ── Batch 1: within-limit behaviour ──────────────────────────────────────────

  describe "check_and_increment/3 within limit" do
    test "allows a single request" do
      assert :ok = RateLimiter.check_and_increment("bucket", 3, 60_000)
    end

    test "allows requests up to the limit" do
      assert :ok = RateLimiter.check_and_increment("bucket", 3, 60_000)
      assert :ok = RateLimiter.check_and_increment("bucket", 3, 60_000)
      assert :ok = RateLimiter.check_and_increment("bucket", 3, 60_000)
    end
  end

  # ── Batch 2: over-limit behaviour ────────────────────────────────────────────

  describe "check_and_increment/3 over limit" do
    test "blocks the request that exceeds the limit" do
      RateLimiter.check_and_increment("bucket", 2, 60_000)
      RateLimiter.check_and_increment("bucket", 2, 60_000)
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("bucket", 2, 60_000)
    end

    test "continues blocking subsequent requests after limit is exceeded" do
      RateLimiter.check_and_increment("bucket", 1, 60_000)
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("bucket", 1, 60_000)
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("bucket", 1, 60_000)
    end
  end

  # ── Batch 3: window reset ─────────────────────────────────────────────────────

  describe "check_and_increment/3 window reset" do
    test "resets the counter after the window expires" do
      assert :ok = RateLimiter.check_and_increment("bucket", 1, 1)
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("bucket", 1, 1)

      # Wait for window to expire
      Process.sleep(10)

      assert :ok = RateLimiter.check_and_increment("bucket", 1, 1)
    end
  end

  # ── Batch 4: bucket isolation ─────────────────────────────────────────────────

  describe "check_and_increment/3 bucket isolation" do
    test "different buckets have independent counters" do
      assert :ok = RateLimiter.check_and_increment("bucket_a", 1, 60_000)
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("bucket_a", 1, 60_000)
      assert :ok = RateLimiter.check_and_increment("bucket_b", 1, 60_000)
    end

    test "tuple buckets can be used for namespaced keys" do
      assert :ok = RateLimiter.check_and_increment({:auth, "1.2.3.4"}, 2, 60_000)
      assert :ok = RateLimiter.check_and_increment({:auth, "1.2.3.4"}, 2, 60_000)

      assert {:error, :rate_limited} =
               RateLimiter.check_and_increment({:auth, "1.2.3.4"}, 2, 60_000)

      assert :ok = RateLimiter.check_and_increment({:auth, "5.6.7.8"}, 2, 60_000)
    end
  end
end
