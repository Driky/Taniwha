defmodule TaniwhaWeb.SessionControllerTest do
  use TaniwhaWeb.ConnCase, async: false

  alias Taniwha.Auth.CredentialStore

  setup do
    username = "session_ctrl_#{System.unique_integer([:positive])}"
    {:ok, user} = CredentialStore.create_user(username, "Test_password_123!")
    on_exit(fn -> CredentialStore.delete_user(user.id) end)
    {:ok, user: user, username: username, password: "Test_password_123!"}
  end

  describe "POST /session (create)" do
    test "valid credentials set user_id in session and redirect to /",
         %{conn: conn, username: username, password: password} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> post(~p"/session", %{username: username, password: password})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, "user_id") != nil
    end

    test "invalid password redirects to /login and does not set session",
         %{conn: conn, username: username} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> post(~p"/session", %{username: username, password: "wrongpassword"})

      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, "user_id") == nil
    end

    test "unknown username redirects to /login and does not set session",
         %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> post(~p"/session", %{username: "nobody_here", password: "anything"})

      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, "user_id") == nil
    end
  end

  describe "DELETE /session (delete)" do
    test "clears session and redirects to /login", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/session")

      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, "user_id") == nil
    end
  end
end
