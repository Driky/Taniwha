defmodule TaniwhaWeb.AddTorrentTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Taniwha.State.Store

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

  # ---------------------------------------------------------------------------
  # Batch 5 — Modal open/close skeleton
  # ---------------------------------------------------------------------------

  describe "add torrent modal" do
    test "modal is hidden by default on dashboard", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ ~s(role="dialog")
      refute html =~ "Add Torrent"
    end

    test "clicking Add torrent button opens the modal", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()

      html = render(lv)
      assert html =~ ~s(role="dialog")
    end

    test "modal has aria-modal=true", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()

      assert render(lv) =~ ~s(aria-modal="true")
    end

    test "URL tab is active by default", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()

      assert render(lv) =~ ~s(aria-selected="true")
    end

    test "pressing Escape closes the modal", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()
      render_keydown(lv, "keydown", %{"key" => "Escape"})

      refute render(lv) =~ ~s(role="dialog")
    end

    test "clicking backdrop closes the modal", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()
      render_click(lv, "hide_add_modal", %{})

      refute render(lv) =~ ~s(role="dialog")
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6 — URL submission
  # ---------------------------------------------------------------------------

  describe "URL submission" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()
      {:ok, lv: lv}
    end

    test "submitting valid magnet URL calls Commands.load_url/1", %{lv: lv} do
      url = "magnet:?xt=urn:btih:abc123"
      expect(Taniwha.MockCommands, :load_url, fn ^url -> :ok end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => url})
    end

    test "on :ok closes modal and shows success flash", %{lv: lv} do
      stub(Taniwha.MockCommands, :load_url, fn _url -> :ok end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => "magnet:?xt=urn:btih:abc123"})

      html = render(lv)
      refute html =~ ~s(role="dialog")
      assert html =~ "Torrent added"
    end

    test "on {:error, _} stays open and shows error", %{lv: lv} do
      stub(Taniwha.MockCommands, :load_url, fn _url -> {:error, :timeout} end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => "magnet:?xt=urn:btih:abc123"})

      html = render(lv)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(role="alert")
    end

    test "empty URL shows validation error without calling Commands", %{lv: lv} do
      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => ""})

      html = render(lv)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(role="alert")
    end

    test "switching to file tab hides URL form", %{lv: lv} do
      lv
      |> element("[phx-click=switch_tab][phx-value-tab=file]")
      |> render_click()

      html = render(lv)
      # file upload input should be present
      assert html =~ "live_file_input" or html =~ ~s(type="file")
      # URL form not active
      refute html =~ ~s(phx-submit="submit_url")
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 7 — File upload
  # ---------------------------------------------------------------------------

  describe "file upload" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()
      lv |> element("[phx-click=switch_tab][phx-value-tab=file]") |> render_click()
      {:ok, lv: lv}
    end

    test "file tab shows upload input", %{lv: lv} do
      html = render(lv)
      assert html =~ ~s(type="file") or html =~ "drop"
    end

    test "uploading .torrent file and submitting calls Commands.load_raw/1", %{
      lv: lv,
      conn: conn
    } do
      content = "torrent file binary content"
      expect(Taniwha.MockCommands, :load_raw, fn ^content -> :ok end)

      lv
      |> file_input("#add-torrent-modal form", :torrent_file, [
        %{
          name: "test.torrent",
          content: content,
          type: "application/x-bittorrent"
        }
      ])
      |> render_upload("test.torrent", 100)

      lv
      |> element("form[phx-submit=submit_file]")
      |> render_submit()

      # Modal closes and flash shows
      html = render(lv)
      refute html =~ ~s(role="dialog")
      assert html =~ "Torrent added"
      _ = conn
    end

    test "non-.torrent file shows validation error", %{lv: lv} do
      lv
      |> file_input("#add-torrent-modal form", :torrent_file, [
        %{name: "image.png", content: "png content", type: "image/png"}
      ])
      |> render_upload("image.png", 100)

      html = render(lv)
      # Upload validation should show an error
      assert html =~ "not-allowed" or html =~ "error" or html =~ "invalid"
    end
  end
end
