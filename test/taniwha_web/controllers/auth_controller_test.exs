defmodule TaniwhaWeb.AuthControllerTest do
  use TaniwhaWeb.ConnCase, async: true

  describe "POST /api/v1/auth/token" do
    test "returns JWT token with correct API key", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/token", %{api_key: "test-api-key-for-tests"})

      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token)
    end

    test "returns 401 with incorrect API key", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/token", %{api_key: "wrong-key"})

      assert %{"error" => "invalid_api_key"} = json_response(conn, 401)
    end

    test "returns 400 when api_key param is missing", %{conn: conn} do
      conn = post(conn, "/api/v1/auth/token", %{})

      assert %{"error" => "api_key is required"} = json_response(conn, 400)
    end
  end
end
