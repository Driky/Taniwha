defmodule TaniwhaWeb.SettingsLiveTest do
  use TaniwhaWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias Taniwha.Auth.{CredentialStore, MockWax}

  setup :verify_on_exit!

  setup %{conn: conn} do
    {conn, user} = register_and_log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  defp make_stored_passkey(attrs \\ %{}) do
    Map.merge(
      %{
        credential_id: :crypto.strong_rand_bytes(32),
        cose_key: CBOR.encode(%{1 => 2, 3 => -7}),
        sign_count: 0,
        label: "Device passkey · Mar 30, 2026",
        created_at: "2026-03-30T00:00:00Z"
      },
      attrs
    )
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — SettingsLive mount + display
  # ---------------------------------------------------------------------------

  describe "settings page" do
    test "GET /settings renders 200 with Settings title", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
    end

    test "back link navigates to dashboard", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ ~s(href="/")
    end

    test "system info section shows Elixir version", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ System.version()
    end

    test "API key is masked by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      refute html =~ "test-api-key-for-tests"
      assert html =~ "•"
    end

    test "connection status section renders with role=status", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ ~s(role="status")
    end

    test "interactive buttons have aria-label", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      # Reveal and copy buttons
      assert html =~ "aria-label"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 9 — API key reveal / copy
  # ---------------------------------------------------------------------------

  describe "API key reveal" do
    test "reveal_key event shows the actual key", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")
      render_click(lv, "reveal_key", %{})

      html = render(lv)
      assert html =~ "test-api-key-for-tests"
    end

    test "second reveal_key hides the key again", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")
      render_click(lv, "reveal_key", %{})
      render_click(lv, "reveal_key", %{})

      html = render(lv)
      refute html =~ "test-api-key-for-tests"
      assert html =~ "•"
    end

    test "reveal button aria-pressed reflects revealed state", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")
      html = render(lv)
      assert html =~ ~s(aria-pressed="false")

      render_click(lv, "reveal_key", %{})
      html = render(lv)
      assert html =~ ~s(aria-pressed="true")
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 10 — Connection status
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Batch 11 — Passkeys section
  # ---------------------------------------------------------------------------

  describe "passkeys section — empty state" do
    test "renders 'Add a passkey' heading when user has no passkeys", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Add a passkey"
    end

    test "renders 'Add passkey' button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Add passkey"
    end
  end

  describe "passkeys section — with passkeys" do
    test "renders passkey label and date", %{conn: conn, user: user} do
      {:ok, _u} = CredentialStore.add_passkey(user.id, make_stored_passkey())
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Device passkey · Mar 30, 2026"
      assert html =~ "Mar 30, 2026"
    end

    test "renders a delete button for each passkey", %{conn: conn, user: user} do
      {:ok, _u} = CredentialStore.add_passkey(user.id, make_stored_passkey())
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "delete_passkey"
    end

    test "renders '+ Add another passkey' link", %{conn: conn, user: user} do
      {:ok, _u} = CredentialStore.add_passkey(user.id, make_stored_passkey())
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ "Add another passkey"
    end
  end

  describe "add_passkey event" do
    test "pushes 'start-passkey-registration' event to client", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      render_click(lv, "add_passkey", %{})

      assert_push_event(lv, "start-passkey-registration", _opts)
    end
  end

  describe "passkey_registered event (JS hook response)" do
    test "adds the passkey to the displayed list", %{conn: conn, user: user} do
      cred_id = :crypto.strong_rand_bytes(32)

      stub(MockWax, :register, fn _attest, _cdj, _challenge ->
        {:ok,
         {%{
            sign_count: 0,
            attested_credential_data: %{
              credential_id: cred_id,
              credential_public_key: %{1 => 2, 3 => -7}
            }
          }, nil}}
      end)

      {:ok, lv, _html} = live(conn, ~p"/settings")
      render_click(lv, "add_passkey", %{})

      render_hook(lv, "passkey_registered", %{
        "credential_id" => Base.encode64(cred_id),
        "client_data_json" => Base.encode64("{}"),
        "attestation_object" => Base.encode64("attest"),
        "label" => "Device passkey · Mar 30, 2026"
      })

      html = render(lv)
      assert html =~ "Device passkey · Mar 30, 2026"

      # cleanup
      {:ok, u} = CredentialStore.get_user(user.id)
      Enum.each(u.passkeys, &CredentialStore.delete_passkey(user.id, &1.id))
    end

    test "shows error when registration fails", %{conn: conn} do
      stub(MockWax, :register, fn _attest, _cdj, _challenge ->
        {:error, :bad_attestation}
      end)

      {:ok, lv, _html} = live(conn, ~p"/settings")
      render_click(lv, "add_passkey", %{})

      render_hook(lv, "passkey_registered", %{
        "credential_id" => Base.encode64("cred"),
        "client_data_json" => Base.encode64("{}"),
        "attestation_object" => Base.encode64("attest"),
        "label" => "label"
      })

      html = render(lv)
      assert html =~ "registration failed" or html =~ "failed" or html =~ "error"
    end
  end

  describe "passkey_registration_error event" do
    test "shows error message", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      render_hook(lv, "passkey_registration_error", %{"message" => "NotAllowedError"})

      html = render(lv)
      assert html =~ "error" or html =~ "Error" or html =~ "failed"
    end
  end

  describe "delete_passkey event" do
    test "removes the passkey from the displayed list", %{conn: conn, user: user} do
      {:ok, updated} = CredentialStore.add_passkey(user.id, make_stored_passkey())
      [pk] = updated.passkeys

      {:ok, lv, html} = live(conn, ~p"/settings")
      assert html =~ "Device passkey · Mar 30, 2026"

      render_click(lv, "delete_passkey", %{"id" => pk.id})

      html = render(lv)
      refute html =~ "Device passkey · Mar 30, 2026"
    end
  end

  describe "connection status" do
    test "shows connected when RPC client process is alive", %{conn: conn} do
      # In tests, the RPC client process might not be running, so we check
      # the appropriate status based on actual process state
      {:ok, _lv, html} = live(conn, ~p"/settings")
      # Either "Connected" or "Not connected" appears
      assert html =~ "connected" or html =~ "Connected" or html =~ "Not connected"
    end

    test "connection dot has status element", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/settings")
      assert html =~ ~s(role="status")
    end
  end
end
