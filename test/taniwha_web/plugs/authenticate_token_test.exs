defmodule TaniwhaWeb.Plugs.AuthenticateTokenTest do
  use TaniwhaWeb.ConnCase, async: true

  alias TaniwhaWeb.Plugs.AuthenticateToken

  setup do
    {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")
    {:ok, token: token}
  end

  describe "call/2" do
    test "assigns :current_user and passes conn through with valid Bearer token",
         %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> AuthenticateToken.call(%{})

      assert conn.assigns[:current_user] == "api_user"
      refute conn.halted
    end

    test "halts with 401 when Authorization header is missing", %{conn: conn} do
      conn = AuthenticateToken.call(conn, %{})

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "halts with 401 when token is malformed", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer garbage_token")
        |> AuthenticateToken.call(%{})

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end

    test "halts with 401 when scheme is not Bearer", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Token #{token}")
        |> AuthenticateToken.call(%{})

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body) == %{"error" => "unauthorized"}
    end
  end
end
