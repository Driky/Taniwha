defmodule TaniwhaWeb.AddTorrentTest do
  use TaniwhaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  alias Taniwha.State.Store
  alias Taniwha.Test.Fixtures

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

    test "submitting valid magnet URL calls Commands.load_urls/2", %{lv: lv} do
      url = "magnet:?xt=urn:btih:abc123"
      expect(Taniwha.MockCommands, :load_urls, fn [^url], _opts -> {:ok, 1} end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url}})
    end

    test "on {:ok, _} closes modal and shows success flash", %{lv: lv} do
      stub(Taniwha.MockCommands, :load_urls, fn _urls, _opts -> {:ok, 1} end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => "magnet:?xt=urn:btih:abc123"}})

      html = render(lv)
      refute html =~ ~s(role="dialog")
      assert html =~ "Torrent added"
    end

    test "on {:error, _} stays open and shows error", %{lv: lv} do
      stub(Taniwha.MockCommands, :load_urls, fn _urls, _opts ->
        {:error, [{"magnet:?xt=urn:btih:abc123", :timeout}]}
      end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => "magnet:?xt=urn:btih:abc123"}})

      html = render(lv)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(role="alert")
    end

    test "empty URL shows validation error without calling Commands", %{lv: lv} do
      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => ""}})

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

    test "uploading single .torrent file and submitting calls Commands.load_raws/2", %{
      lv: lv,
      conn: conn
    } do
      content = "torrent file binary content"
      expect(Taniwha.MockCommands, :load_raws, fn [^content], _opts -> {:ok, 1} end)

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

      html = render(lv)
      refute html =~ ~s(role="dialog")
      assert html =~ "Torrent added"
      _ = conn
    end

    # NOTE: Phoenix LiveViewTest does not support testing multi-file upload submissions
    # end-to-end: consuming the first file's upload channel tears down the shared
    # UploadClient transport, making subsequent channels unreachable.  Multi-file
    # submission behaviour is covered at the Commands layer (load_raws/2 unit tests)
    # and via manual smoke tests (task 6.3–6.5).

    test "multiple .torrent files can be queued before submit (max_entries: 20)",
         %{lv: lv} do
      upload =
        file_input(lv, "#add-torrent-modal form", :torrent_file, [
          %{name: "a.torrent", content: "AAA", type: "application/x-bittorrent"},
          %{name: "b.torrent", content: "BBB", type: "application/x-bittorrent"}
        ])

      # Both files should be allowed into the upload queue without a :too_many_files error.
      html_a = render_upload(upload, "a.torrent", 50)
      html_b = render_upload(upload, "b.torrent", 50)

      # No error banner should appear for either upload.
      refute html_a =~ "Too many files"
      refute html_b =~ "Too many files"
    end

    test "Commands.load_raws failure keeps modal open and shows error", %{lv: lv} do
      content = "some torrent"

      expect(Taniwha.MockCommands, :load_raws, fn [^content], _opts ->
        {:error, [{0, :timeout}]}
      end)

      upload =
        file_input(lv, "#add-torrent-modal form", :torrent_file, [
          %{name: "test.torrent", content: content, type: "application/x-bittorrent"}
        ])

      render_upload(upload, "test.torrent", 100)

      lv
      |> element("form[phx-submit=submit_file]")
      |> render_submit()

      html = render(lv)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(role="alert")
    end

    test "non-.torrent file shows validation error", %{lv: lv} do
      lv
      |> file_input("#add-torrent-modal form", :torrent_file, [
        %{name: "image.png", content: "png content", type: "image/png"}
      ])
      |> render_upload("image.png", 100)

      html = render(lv)
      assert html =~ "not-allowed" or html =~ "error" or html =~ "invalid"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — Label selector in URL tab
  # ---------------------------------------------------------------------------

  describe "label selector in URL tab" do
    setup %{conn: conn} do
      t = %{Fixtures.torrent_fixture("h1") | label: "Movies"}
      Store.put_torrent(t)

      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()
      {:ok, lv: lv}
    end

    test "shows label buttons for existing labels", %{lv: lv} do
      html = render(lv)
      assert html =~ ~r/phx-click="select_label"[^>]*phx-value-label="Movies"/
    end

    test "clicking a label selects it (aria-pressed=true)", %{lv: lv} do
      lv
      |> element("[phx-click=select_label][phx-value-label=Movies]")
      |> render_click()

      html = render(lv)
      assert html =~ ~r/phx-value-label="Movies"[^>]*aria-pressed="true"/
    end

    test "clicking the selected label again deselects it", %{lv: lv} do
      lv |> element("[phx-click=select_label][phx-value-label=Movies]") |> render_click()
      lv |> element("[phx-click=select_label][phx-value-label=Movies]") |> render_click()

      html = render(lv)
      assert html =~ ~r/phx-value-label="Movies"[^>]*aria-pressed="false"/
    end

    test "submitting URL with selected label passes label: opt to load_urls", %{lv: lv} do
      url = "magnet:?xt=urn:btih:abc123"
      expect(Taniwha.MockCommands, :load_urls, fn [^url], [label: "Movies"] -> {:ok, 1} end)

      lv |> element("[phx-click=select_label][phx-value-label=Movies]") |> render_click()

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url}})
    end

    test "submitting URL without selection passes empty opts", %{lv: lv} do
      url = "magnet:?xt=urn:btih:abc123"
      expect(Taniwha.MockCommands, :load_urls, fn [^url], [] -> {:ok, 1} end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url}})
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 9 — Multi-URL event handlers
  # ---------------------------------------------------------------------------

  describe "multi-URL fields" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      lv |> element("[phx-click=show_add_modal]") |> render_click()
      {:ok, lv: lv}
    end

    test "initial state has one URL field", %{lv: lv} do
      html = render(lv)
      assert html =~ ~s(add-torrent-modal-url-input-0)
      refute html =~ ~s(add-torrent-modal-url-input-1)
    end

    test "clicking + adds a second URL field", %{lv: lv} do
      lv |> element("[phx-click=add_url_field]") |> render_click()
      html = render(lv)
      assert html =~ ~s(add-torrent-modal-url-input-1)
    end

    test "clicking - on second field removes it", %{lv: lv} do
      lv |> element("[phx-click=add_url_field]") |> render_click()
      lv |> element("[phx-click=remove_url_field][phx-value-index=\"1\"]") |> render_click()
      html = render(lv)
      refute html =~ ~s(add-torrent-modal-url-input-1)
    end

    test "switching to file tab resets url fields to one empty field", %{lv: lv} do
      lv |> element("[phx-click=add_url_field]") |> render_click()
      lv |> element("[phx-click=switch_tab][phx-value-tab=file]") |> render_click()
      lv |> element("[phx-click=switch_tab][phx-value-tab=url]") |> render_click()
      html = render(lv)
      refute html =~ ~s(add-torrent-modal-url-input-1)
    end

    test "submitting multiple URLs calls load_urls/2 with all non-blank values", %{lv: lv} do
      url_a = "magnet:?xt=urn:btih:aaaaaa"
      url_b = "magnet:?xt=urn:btih:bbbbbb"

      expect(Taniwha.MockCommands, :load_urls, fn [^url_a, ^url_b], _opts -> {:ok, 2} end)

      lv |> element("[phx-click=add_url_field]") |> render_click()

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url_a, "1" => url_b}})

      html = render(lv)
      refute html =~ ~s(role="dialog")
    end

    test "partial URL failure shows error and removes succeeded urls", %{lv: lv} do
      url_a = "magnet:?xt=urn:btih:aaaaaa"
      url_b = "magnet:?xt=urn:btih:bbbbbb"

      expect(Taniwha.MockCommands, :load_urls, fn [^url_a, ^url_b], _opts ->
        {:error, [{url_b, :timeout}]}
      end)

      lv |> element("[phx-click=add_url_field]") |> render_click()

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url_a, "1" => url_b}})

      html = render(lv)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(role="alert")
      # succeeded url (url_a) removed; failed url (url_b) remains
      refute html =~ url_a
      assert html =~ url_b
    end

    test "blank URLs are filtered out before submission", %{lv: lv} do
      url_a = "magnet:?xt=urn:btih:aaaaaa"

      expect(Taniwha.MockCommands, :load_urls, fn [^url_a], _opts -> {:ok, 1} end)

      lv |> element("[phx-click=add_url_field]") |> render_click()

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url_a, "1" => ""}})

      html = render(lv)
      refute html =~ ~s(role="dialog")
    end

    test "+ button is disabled when 20 URL fields are present", %{lv: lv} do
      # Add 19 more fields (starting from 1 already present).
      # Target the first row's + button using the sibling combinator to avoid
      # the multi-element ambiguity when more than one + button is rendered.
      Enum.each(1..19, fn _ ->
        lv
        |> element("#add-torrent-modal-url-input-0 ~ button[phx-click=add_url_field]")
        |> render_click()
      end)

      html = render(lv)
      assert html =~ ~s(add-torrent-modal-url-input-19)
      # The + button should be disabled
      assert html =~ ~s(disabled)
    end

    test "batch failure renders a structured error list", %{lv: lv} do
      url_a = "magnet:?xt=urn:btih:aaaaaa"
      url_b = "magnet:?xt=urn:btih:bbbbbb"

      expect(Taniwha.MockCommands, :load_urls, fn [^url_a, ^url_b], _opts ->
        {:error, [{url_a, :timeout}, {url_b, :timeout}]}
      end)

      lv |> element("[phx-click=add_url_field]") |> render_click()

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => %{"0" => url_a, "1" => url_b}})

      html = render(lv)
      assert html =~ ~s(role="alert")
      assert html =~ "Failed to add 2 item(s)"
      assert html =~ "<ul"
    end
  end
end
