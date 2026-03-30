defmodule TaniwhaWeb.LoginLiveTest do
  use TaniwhaWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias Taniwha.Auth.{CredentialStore, MockWax}

  setup :verify_on_exit!

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

    test "clicking passkey button fires start-passkey-login push event", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      render_click(lv, "use_passkey", %{})
      assert_push_event(lv, "start-passkey-login", _opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6 — passkey login flow
  # ---------------------------------------------------------------------------

  describe "passkey form" do
    test "passkey hidden form is always present in HTML", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ "passkey-form"
    end

    test "passkey form phx-trigger-action is false on initial render", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")
      assert html =~ ~s(id="passkey-form")
      refute html =~ ~s(phx-trigger-action="true")
    end
  end

  describe "use_passkey event" do
    test "assigns webauthn challenge and fires start-passkey-login event", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      render_click(lv, "use_passkey", %{})
      assert_push_event(lv, "start-passkey-login", %{challenge: _, rpId: _})
    end
  end

  describe "passkey_asserted event" do
    test "success sets trigger_submit_passkey and shows passkey form ready to submit",
         %{conn: conn, user: user} do
      cred_id = :crypto.strong_rand_bytes(32)

      {:ok, _u} =
        CredentialStore.add_passkey(user.id, %{
          credential_id: cred_id,
          cose_key: CBOR.encode(%{1 => 2, 3 => -7}),
          sign_count: 0,
          label: "Test passkey",
          created_at: "2026-03-30T00:00:00Z"
        })

      stub(MockWax, :authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:ok, %{sign_count: 1}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/login")
      render_click(lv, "use_passkey", %{})

      render_hook(lv, "passkey_asserted", %{
        "credential_id" => Base.encode64(cred_id),
        "authenticator_data" => Base.encode64("auth_data"),
        "client_data_json" => Base.encode64("{}"),
        "signature" => Base.encode64("sig")
      })

      html = render(lv)
      # When trigger_submit_passkey=true, passkey_token is populated with a signed Phoenix.Token
      assert html =~ ~r/name="passkey_token" value="SFMyNTY\./
    end

    test "unknown credential_id shows error message", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      render_click(lv, "use_passkey", %{})

      render_hook(lv, "passkey_asserted", %{
        "credential_id" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "authenticator_data" => Base.encode64("auth_data"),
        "client_data_json" => Base.encode64("{}"),
        "signature" => Base.encode64("sig")
      })

      html = render(lv)
      assert html =~ "error" or html =~ "Error" or html =~ "failed" or html =~ "recognized"
    end

    test "assertion failure shows error message", %{conn: conn, user: user} do
      cred_id = :crypto.strong_rand_bytes(32)

      {:ok, _u} =
        CredentialStore.add_passkey(user.id, %{
          credential_id: cred_id,
          cose_key: CBOR.encode(%{1 => 2, 3 => -7}),
          sign_count: 0,
          label: "Test passkey",
          created_at: "2026-03-30T00:00:00Z"
        })

      stub(MockWax, :authenticate, fn _cred_id, _auth_data, _sig, _cdj, _challenge, _creds ->
        {:error, :bad_signature}
      end)

      {:ok, lv, _html} = live(conn, ~p"/login")
      render_click(lv, "use_passkey", %{})

      render_hook(lv, "passkey_asserted", %{
        "credential_id" => Base.encode64(cred_id),
        "authenticator_data" => Base.encode64("auth_data"),
        "client_data_json" => Base.encode64("{}"),
        "signature" => Base.encode64("sig")
      })

      html = render(lv)
      assert html =~ "error" or html =~ "Error" or html =~ "failed"
    end
  end

  describe "passkey_login_error event" do
    test "shows error message near passkey button", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")
      render_hook(lv, "passkey_login_error", %{"message" => "NotAllowedError"})
      html = render(lv)
      assert html =~ "error" or html =~ "Error" or html =~ "failed" or html =~ "cancelled"
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
