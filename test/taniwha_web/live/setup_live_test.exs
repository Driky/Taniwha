defmodule TaniwhaWeb.SetupLiveTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Taniwha.Auth.CredentialStore

  # Clear any persisted users so each test starts from a clean state.
  # CredentialStore persists to disk and users from previous runs carry over.
  setup do
    CredentialStore.list_users()
    |> Enum.each(&CredentialStore.delete_user(&1.id))

    :ok
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — SetupLive
  # ---------------------------------------------------------------------------

  describe "GET /setup when no users exist" do
    test "renders setup form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/setup")

      assert html =~ "Create admin account"
      assert html =~ "Username"
      assert html =~ "Password"
      assert html =~ "Confirm Password"
    end
  end

  describe "GET /setup when users already exist" do
    setup do
      username = "setup_existing_#{System.unique_integer([:positive])}"
      {:ok, user} = CredentialStore.create_user(username, "Test_password_123!")
      on_exit(fn -> CredentialStore.delete_user(user.id) end)
      {:ok, user: user}
    end

    test "redirects to /login", %{conn: conn} do
      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/setup")
      assert path == "/login"
    end
  end

  describe "form submission" do
    test "valid submission creates admin user and redirects to /login",
         %{conn: conn} do
      username = "new_admin_#{System.unique_integer([:positive])}"

      {:ok, lv, _html} = live(conn, ~p"/setup")

      result =
        lv
        |> form("#setup-form", %{
          username: username,
          password: "SecurePass1!",
          password_confirmation: "SecurePass1!"
        })
        |> render_submit()

      # On success, SetupLive does push_navigate to /login
      assert {:error, {:live_redirect, %{to: "/login"}}} = result

      # The user was created
      assert {:ok, _} = CredentialStore.get_user_by_username(username)

      # Cleanup
      {:ok, user} = CredentialStore.get_user_by_username(username)
      CredentialStore.delete_user(user.id)
    end

    test "mismatched passwords shows error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/setup")

      html =
        lv
        |> form("#setup-form", %{
          username: "admin",
          password: "SecurePass1!",
          password_confirmation: "DifferentPass1!"
        })
        |> render_submit()

      assert html =~ "Passwords do not match"
    end

    test "password shorter than 8 chars shows error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/setup")

      html =
        lv
        |> form("#setup-form", %{
          username: "admin",
          password: "short",
          password_confirmation: "short"
        })
        |> render_submit()

      assert html =~ "at least 8 characters"
    end

    test "blank username shows error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/setup")

      html =
        lv
        |> form("#setup-form", %{
          username: "",
          password: "SecurePass1!",
          password_confirmation: "SecurePass1!"
        })
        |> render_submit()

      assert html =~ "cannot be blank"
    end

    test "race condition guard: re-checks has_any_users? on submit", %{conn: conn} do
      # Mount while no users exist (renders form)
      {:ok, lv, _html} = live(conn, ~p"/setup")

      # A second admin is created by another process while the form is open
      concurrent_user = "concurrent_#{System.unique_integer([:positive])}"
      {:ok, concurrent} = CredentialStore.create_user(concurrent_user, "Test_password_123!")

      html =
        lv
        |> form("#setup-form", %{
          username: "late_admin",
          password: "SecurePass1!",
          password_confirmation: "SecurePass1!"
        })
        |> render_submit()

      assert html =~ "already been configured"

      CredentialStore.delete_user(concurrent.id)
    end

    test "strength bar shows weak indicator for short password (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/setup")

      html =
        lv
        |> form("#setup-form", %{password: "short"})
        |> render_change()

      assert html =~ "bg-red-500"
    end

    test "strength bar shows strong indicator for long password (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/setup")

      html =
        lv
        |> form("#setup-form", %{password: "longenough"})
        |> render_change()

      assert html =~ "bg-green-500"
    end
  end
end
