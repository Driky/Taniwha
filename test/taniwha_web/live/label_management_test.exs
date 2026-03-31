defmodule TaniwhaWeb.LabelManagementTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Taniwha.{MockCommands, State.Store}
  alias Taniwha.Test.Fixtures

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Store.clear()
    on_exit(fn -> Store.clear() end)
    :ok
  end

  setup %{conn: conn} do
    {conn, _user} = register_and_log_in_user(conn)
    {:ok, conn: conn}
  end

  # ── Batch B1: modal visibility ────────────────────────────────────────────

  describe "label manager modal" do
    test "is not rendered on initial load", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      refute html =~
               ~r/role="dialog"[^>]+aria-label[^>]+[Ll]abels|aria-label[^>]+[Ll]abels[^>]+role="dialog"/
    end

    test "opens when 'Manage labels' button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      html = lv |> element("button[phx-click=show_label_manager]") |> render_click()
      assert html =~ "label-manager-modal"
    end

    test "closes when close button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=show_label_manager]") |> render_click()

      lv
      |> element("[id=label-manager-modal] button[aria-label='Close label manager']")
      |> render_click()

      # render/1 ensures parent handle_info(:hide_label_manager) has fired
      html = render(lv)
      refute html =~ "label-manager-modal"
    end
  end

  # ── Batch B2: listing labels ──────────────────────────────────────────────

  describe "label manager — listing labels" do
    test "shows existing labels with their counts", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie 1"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Movies", name: "Movie 2"}
      t3 = %{Fixtures.torrent_fixture("h3") | label: "Linux", name: "Linux ISO"}
      Enum.each([t1, t2, t3], &Store.put_torrent/1)

      {:ok, lv, _html} = live(conn, ~p"/")
      html = lv |> element("button[phx-click=show_label_manager]") |> render_click()

      assert html =~ "Movies"
      assert html =~ "Linux"
    end

    test "shows empty state when no labels exist", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      html = lv |> element("button[phx-click=show_label_manager]") |> render_click()
      assert html =~ "No labels yet"
    end
  end

  # ── Batch B3: creating a label ────────────────────────────────────────────

  describe "label manager — creating a label" do
    test "creates a new label via the form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=show_label_manager]") |> render_click()

      lv
      |> element("[id=label-manager-modal] form[phx-submit=create_label]")
      |> render_submit(%{"label_name" => "NewLabel", "color" => "#ec4899"})

      # render/1 after render_submit ensures parent handle_info(:label_created) has fired
      html = render(lv)
      assert html =~ "NewLabel"
    end

    test "does nothing when name is blank", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=show_label_manager]") |> render_click()

      html =
        lv
        |> element("[id=label-manager-modal] form[phx-submit=create_label]")
        |> render_submit(%{"label_name" => "   ", "color" => "#ec4899"})

      # Modal stays open, no new label
      assert html =~ "label-manager-modal"
    end
  end

  # ── Batch B4: deleting a label ────────────────────────────────────────────

  describe "label manager — deleting a label" do
    test "removes label from all affected torrents and closes modal", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies", name: "Movie 1"}
      t2 = %{Fixtures.torrent_fixture("h2") | label: "Linux", name: "Linux ISO"}
      Enum.each([t1, t2], &Store.put_torrent/1)

      expect(MockCommands, :remove_label, fn "h1" -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=show_label_manager]") |> render_click()

      lv
      |> element(
        "[id=label-manager-modal] button[phx-click=delete_label][phx-value-label=Movies]"
      )
      |> render_click()

      # render/1 after render_click ensures parent handle_info(:label_deleted) has fired
      html = render(lv)
      refute html =~ ~r/phx-value-label="Movies"/
      assert html =~ "Linux"
    end
  end

  # ── Batch B5: renaming a label ────────────────────────────────────────────

  describe "label manager — renaming a label" do
    test "enters edit mode when edit button clicked", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies"}
      Store.put_torrent(t1)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=show_label_manager]") |> render_click()

      html =
        lv
        |> element(
          "[id=label-manager-modal] button[phx-click=start_edit][phx-value-label=Movies]"
        )
        |> render_click()

      # Edit form should be visible
      assert html =~ ~r/<input[^>]+name="new_name"[^>]+value="Movies"/
    end

    test "renames label across all torrents on save", %{conn: conn} do
      t1 = %{Fixtures.torrent_fixture("h1") | label: "Movies"}
      Store.put_torrent(t1)

      expect(MockCommands, :rename_label, fn "Movies", "Films" -> {:ok, 1} end)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("button[phx-click=show_label_manager]") |> render_click()

      lv
      |> element("[id=label-manager-modal] button[phx-click=start_edit][phx-value-label=Movies]")
      |> render_click()

      lv
      |> element("[id=label-manager-modal] form[phx-submit=save_edit]")
      |> render_submit(%{"new_name" => "Films", "color" => "#ec4899"})

      # render/1 after render_submit ensures parent handle_info(:label_renamed) has fired
      html = render(lv)
      assert html =~ "Films"
      refute html =~ ~r/phx-value-label="Movies"/
    end
  end
end
