defmodule TaniwhaWeb.Plugs.AuthenticateTokenLoggingTest do
  @moduledoc """
  Tests for structured log output from `TaniwhaWeb.Plugs.AuthenticateToken`.

  Verifies that:
  - Authentication failures emit a structured warning log
  - The warning includes remote_ip (for security monitoring) but NOT the token
  - No sensitive data (JWT token, API key) appears in log output

  Must run `async: false` because LogCapture modifies global :logger state.
  """

  use TaniwhaWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Taniwha.LogCapture

  alias TaniwhaWeb.Plugs.AuthenticateToken

  # ---------------------------------------------------------------------------
  # Auth failure logging
  # ---------------------------------------------------------------------------

  describe "authentication failure logging" do
    test "emits warning when Authorization header is missing", %{conn: conn} do
      log = capture_log(fn -> AuthenticateToken.call(conn, %{}) end)

      assert log =~ "Authentication failed"
    end

    test "emits warning when token is malformed", %{conn: conn} do
      log =
        capture_log(fn ->
          conn
          |> put_req_header("authorization", "Bearer garbage_token")
          |> AuthenticateToken.call(%{})
        end)

      assert log =~ "Authentication failed"
    end

    test "warning includes remote_ip in metadata", %{conn: conn} do
      events =
        capture_log_events([level: :warning], fn ->
          AuthenticateToken.call(conn, %{})
        end)

      event = find_event(events, "Authentication failed")
      assert event != nil, "Expected to find 'Authentication failed' log event"
      assert log_meta(event, :remote_ip) != nil
    end

    test "warning includes reason in metadata", %{conn: conn} do
      events =
        capture_log_events([level: :warning], fn ->
          AuthenticateToken.call(conn, %{})
        end)

      event = find_event(events, "Authentication failed")
      assert event != nil
      assert log_meta(event, :reason) != nil
    end

    test "JWT token is NOT logged when auth fails", %{conn: conn} do
      {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")

      # Pass an expired or wrong token to trigger auth failure
      log =
        capture_log(fn ->
          conn
          |> put_req_header("authorization", "Bearer #{token}_corrupted")
          |> AuthenticateToken.call(%{})
        end)

      refute log =~ token
    end

    test "API key is NOT logged when auth fails", %{conn: conn} do
      api_key = Application.get_env(:taniwha, :api_key, "")

      log = capture_log(fn -> AuthenticateToken.call(conn, %{}) end)

      if api_key != "", do: refute(log =~ api_key)
    end

    test "no warning is emitted on successful authentication", %{conn: conn} do
      {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")

      log =
        capture_log(fn ->
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> AuthenticateToken.call(%{})
        end)

      refute log =~ "Authentication failed"
    end
  end
end
