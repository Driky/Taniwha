defmodule TaniwhaWeb.Plugs.AuthenticateSessionTest do
  use TaniwhaWeb.ConnCase, async: false

  alias TaniwhaWeb.Plugs.AuthenticateSession
  alias Taniwha.Auth.CredentialStore

  setup do
    username = "auth_session_test_#{System.unique_integer([:positive])}"
    {:ok, user} = CredentialStore.create_user(username, "Test_password_123!")
    on_exit(fn -> CredentialStore.delete_user(user.id) end)
    {:ok, user: user}
  end

  describe "call/2" do
    test "assigns current_user and passes through with valid user_id in session",
         %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> AuthenticateSession.call(%{})

      assert conn.assigns.current_user.id == user.id
      refute conn.halted
    end

    test "redirects to /login when user_id is missing from session", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> AuthenticateSession.call(%{})

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
    end

    test "redirects to /login when user_id is not found in the store", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{"user_id" => "nonexistent-id-000"})
        |> AuthenticateSession.call(%{})

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
