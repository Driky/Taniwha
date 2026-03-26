defmodule TaniwhaWeb.Plugs.RateLimitTest do
  use TaniwhaWeb.ConnCase, async: false

  alias TaniwhaWeb.Plugs.RateLimit

  # Use a very small window so these tests don't interfere with each other,
  # and clear ETS state before each test for a clean slate.
  @opts RateLimit.init(limit: 3, window_ms: 60_000)

  setup do
    Taniwha.RateLimiter.clear()
    :ok
  end

  # ── Batch 1: pass-through under limit ────────────────────────────────────────

  describe "call/2 within limit" do
    test "passes conn through when under the limit", %{conn: conn} do
      conn = %{conn | remote_ip: {10, 0, 0, 1}}
      result = RateLimit.call(conn, @opts)
      refute result.halted
    end

    test "allows requests up to the limit from same IP", %{conn: conn} do
      conn = %{conn | remote_ip: {10, 0, 0, 2}}

      for _ <- 1..3 do
        result = RateLimit.call(conn, @opts)
        refute result.halted
      end
    end
  end

  # ── Batch 2: 429 over limit ───────────────────────────────────────────────────

  describe "call/2 over limit" do
    test "halts with 429 when limit is exceeded", %{conn: conn} do
      conn = %{conn | remote_ip: {10, 0, 0, 3}}

      for _ <- 1..3, do: RateLimit.call(conn, @opts)

      result = RateLimit.call(conn, @opts)
      assert result.halted
      assert result.status == 429
      assert Jason.decode!(result.resp_body) == %{"error" => "rate_limited"}
    end

    test "includes Retry-After header in 429 response", %{conn: conn} do
      conn = %{conn | remote_ip: {10, 0, 0, 4}}

      for _ <- 1..3, do: RateLimit.call(conn, @opts)

      result = RateLimit.call(conn, @opts)
      assert result.halted
      assert get_resp_header(result, "retry-after") != []
    end
  end

  # ── Batch 3: IP isolation ─────────────────────────────────────────────────────

  describe "call/2 IP isolation" do
    test "different IPs have independent counters", %{conn: conn} do
      conn_a = %{conn | remote_ip: {10, 0, 1, 1}}
      conn_b = %{conn | remote_ip: {10, 0, 1, 2}}

      for _ <- 1..3, do: RateLimit.call(conn_a, @opts)

      blocked = RateLimit.call(conn_a, @opts)
      assert blocked.halted

      allowed = RateLimit.call(conn_b, @opts)
      refute allowed.halted
    end
  end
end
