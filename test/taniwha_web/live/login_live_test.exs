defmodule TaniwhaWeb.LoginLiveTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Taniwha.Auth.CredentialStore

  setup do
    username = "login_live_test_#{System.unique_integer([:positive])}"
    {:ok, user} = CredentialStore.create_user(username, "Test_password_123!")
    on_exit(fn -> CredentialStore.delete_user(user.id) end)
    {:ok, user: user, username: username, password: "Test_password_123!"}
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — LoginLive
  # ---------------------------------------------------------------------------

  describe "GET /login" do
    test "renders login form when unauthenticated", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Sign in"
      assert html =~ "Username"
      assert html =~ "Password"
    end

    test "redirects to / when already authenticated", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/login")
      assert path == "/"
    end
  end

  describe "login form submission" do
    test "valid credentials follow trigger action to session controller",
         %{conn: conn, username: username, password: password} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      form = form(lv, "#login-form", %{username: username, password: password})
      # render_submit fires the login event and sets trigger_submit=true (phx-trigger-action)
      assert render_submit(form) =~ ~r/phx-trigger-action/
      # follow_trigger_action dispatches the HTTP POST to SessionController
      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == ~p"/"
    end

    test "invalid credentials show error message",
         %{conn: conn, username: username} do
      {:ok, lv, _html} = live(conn, ~p"/login")

      html =
        lv
        |> form("#login-form", %{username: username, password: "wrongpassword"})
        |> render_submit()

      assert html =~ "Invalid username or password."
      refute html =~ ~s(phx-trigger-action="true")
    end

    test "unknown username shows error message", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")

      html =
        lv |> form("#login-form", %{username: "nobody", password: "anything"}) |> render_submit()

      assert html =~ "Invalid username or password."
    end

    test "error message is not shown on initial render", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      refute html =~ "Invalid username or password."
    end
  end

  describe "passkey button" do
    test "Use a passkey button is visible", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ "Use a passkey"
    end

    test "clicking passkey button shows coming soon flash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      render_click(lv, "use_passkey", %{})
      # Flash is rendered inline in LoginLive (layout flash is not in render output)
      assert render(lv) =~ "Passkeys are not yet available"
    end
  end

  describe "accessibility" do
    test "username input has associated label", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ ~s(for="username-input")
      assert html =~ ~s(id="username-input")
    end

    test "password input has associated label", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ ~s(for="password-input")
      assert html =~ ~s(id="password-input")
    end

    test "error message has role alert", %{conn: conn, username: username} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      lv |> form("#login-form", %{username: username, password: "wrong"}) |> render_submit()
      html = render(lv)
      assert html =~ ~s(role="alert")
    end
  end
end
