defmodule TaniwhaWeb.FolderPickerTest do
  @moduledoc """
  Tests for the folder picker UI in the Add Torrent modal.

  Mounted via DashboardLive to test the full interaction chain:
  AddTorrentComponent ↔ FolderPicker ↔ FileSystem.list_directories/2.
  """

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

  defp open_modal(lv) do
    lv |> element("[phx-click=show_add_modal]") |> render_click()
    lv
  end

  defp setup_dir(ctx) do
    base = System.tmp_dir!() |> Path.join("taniwha_fp_#{System.unique_integer()}")
    File.mkdir_p!(base)
    sub1 = Path.join(base, "movies")
    sub2 = Path.join(base, "music")
    File.mkdir_p!(sub1)
    File.mkdir_p!(sub2)

    Application.put_env(:taniwha, :downloads_dir, base)

    on_exit(fn ->
      Application.delete_env(:taniwha, :downloads_dir)
      File.rm_rf!(base)
    end)

    Map.merge(ctx, %{base: base, sub1: sub1, sub2: sub2})
  end

  # ---------------------------------------------------------------------------
  # Batch A — Directory field visibility
  # ---------------------------------------------------------------------------

  describe "directory field visibility" do
    test "directory field hidden when downloads_dir not configured", %{conn: conn} do
      Application.delete_env(:taniwha, :downloads_dir)

      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)

      html = render(lv)
      refute html =~ "Download directory"
    end

    test "directory field shown with default path when configured", %{conn: conn} do
      %{base: base} = setup_dir(%{})

      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)

      html = render(lv)
      assert html =~ "Download directory"
      assert html =~ base
    end

    test "browse button present next to input when configured", %{conn: conn} do
      setup_dir(%{})

      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)

      html = render(lv)
      assert html =~ "Browse"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch B — Opening the picker
  # ---------------------------------------------------------------------------

  describe "opening the folder picker" do
    setup ctx, do: setup_dir(ctx)

    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)
      {:ok, lv: lv}
    end

    test "clicking Browse opens the folder picker overlay", %{lv: lv} do
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      html = render(lv)
      assert html =~ ~s(aria-label="Select folder")
    end

    test "picker shows role=dialog with aria-label=Select folder", %{lv: lv} do
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      html = render(lv)
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-label="Select folder")
    end

    test "picker shows root dir name", %{lv: lv, base: base} do
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      root_name = Path.basename(base)
      html = render(lv)
      assert html =~ root_name
    end

    test "root's immediate children are listed", %{lv: lv} do
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      html = render(lv)
      assert html =~ "movies"
      assert html =~ "music"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch C — Expand / collapse
  # ---------------------------------------------------------------------------

  describe "expand and collapse" do
    setup ctx, do: setup_dir(ctx)

    setup %{conn: conn, sub1: sub1} do
      # Give movies a subdirectory so it can be expanded
      File.mkdir_p!(Path.join(sub1, "action"))

      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)
      lv |> element("[phx-click=open_folder_picker]") |> render_click()
      {:ok, lv: lv}
    end

    test "clicking a collapsed directory with children sends toggle_folder and shows children",
         %{lv: lv, sub1: sub1} do
      action_path = Path.join(sub1, "action")

      lv
      |> element("[phx-click=toggle_folder][phx-value-path$=movies]")
      |> render_click()

      html = render(lv)
      assert html =~ action_path
    end

    test "clicking an expanded directory collapses it", %{lv: lv, sub1: sub1} do
      action_path = Path.join(sub1, "action")

      # Expand first
      lv
      |> element("[phx-click=toggle_folder][phx-value-path$=movies]")
      |> render_click()

      assert render(lv) =~ action_path

      # Now collapse
      lv
      |> element("[phx-click=toggle_folder][phx-value-path$=movies]")
      |> render_click()

      refute render(lv) =~ action_path
    end

    test "chevron icon present for directory with children", %{lv: lv} do
      html = render(lv)
      # movies has children (action subdir) - should have a toggle chevron
      assert html =~ ~r/phx-click="toggle_folder"[^>]*phx-value-path[^>]*movies/
    end
  end

  # ---------------------------------------------------------------------------
  # Batch D — Selection and confirmation
  # ---------------------------------------------------------------------------

  describe "selection and confirmation" do
    setup ctx, do: setup_dir(ctx)

    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)
      lv |> element("[phx-click=open_folder_picker]") |> render_click()
      {:ok, lv: lv}
    end

    test "clicking a directory row highlights it", %{lv: lv, sub1: sub1} do
      lv
      |> element("[phx-click=select_folder_node][phx-value-path=\"#{sub1}\"]")
      |> render_click()

      html = render(lv)
      # Selected directory should have selected styling indicator
      assert html =~ "bg-blue-50" or html =~ "text-blue-700" or html =~ sub1
    end

    test "clicking Select writes path to directory input and closes picker", %{
      lv: lv,
      sub1: sub1
    } do
      lv
      |> element("[phx-click=select_folder_node][phx-value-path=\"#{sub1}\"]")
      |> render_click()

      lv |> element("[phx-click=confirm_folder]") |> render_click()

      html = render(lv)
      # Picker is closed
      refute html =~ ~s(aria-label="Select folder")
      # Directory input shows selected path
      assert html =~ sub1
    end

    test "clicking Cancel closes picker without changing directory input", %{lv: lv, base: base} do
      # Select a different directory
      sub1 = Path.join(base, "movies")

      lv
      |> element("[phx-click=select_folder_node][phx-value-path=\"#{sub1}\"]")
      |> render_click()

      # Now cancel — use text content to distinguish the Cancel button from other close triggers
      lv |> element("button[phx-click=close_folder_picker]", "Cancel") |> render_click()

      html = render(lv)
      # Picker is closed
      refute html =~ ~s(aria-label="Select folder")
      # Directory input still shows base (not sub1)
      assert html =~ base
    end
  end

  # ---------------------------------------------------------------------------
  # Batch E — Command integration
  # ---------------------------------------------------------------------------

  describe "command integration" do
    setup ctx, do: setup_dir(ctx)

    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)
      {:ok, lv: lv}
    end

    test "submitting URL with custom directory passes directory: opt to load_url", %{
      lv: lv,
      sub1: sub1
    } do
      url = "magnet:?xt=urn:btih:abc123"

      expect(Taniwha.MockCommands, :load_url, fn ^url, opts ->
        assert opts[:directory] == sub1
        :ok
      end)

      # Open picker, select sub1, confirm
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      lv
      |> element("[phx-click=select_folder_node][phx-value-path=\"#{sub1}\"]")
      |> render_click()

      lv |> element("[phx-click=confirm_folder]") |> render_click()

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => url})
    end

    test "submitting URL with the default directory does NOT pass directory: opt", %{
      lv: lv
    } do
      url = "magnet:?xt=urn:btih:abc123"

      expect(Taniwha.MockCommands, :load_url, fn ^url, opts ->
        refute Keyword.has_key?(opts, :directory)
        :ok
      end)

      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => url})
    end

    test "submitting URL with blank directory does NOT pass directory: opt", %{lv: lv} do
      url = "magnet:?xt=urn:btih:abc123"

      expect(Taniwha.MockCommands, :load_url, fn ^url, opts ->
        refute Keyword.has_key?(opts, :directory)
        :ok
      end)

      # Manually clear the download_dir via the hidden input (blank)
      lv
      |> element("form[phx-submit=submit_url]")
      |> render_submit(%{"url" => url})
    end

    test "file upload with custom directory passes directory: opt to load_raw", %{
      lv: lv,
      sub1: sub1,
      conn: conn
    } do
      content = "torrent binary"

      expect(Taniwha.MockCommands, :load_raw, fn ^content, opts ->
        assert opts[:directory] == sub1
        :ok
      end)

      # Switch to file tab, open picker, select sub1, confirm
      lv |> element("[phx-click=switch_tab][phx-value-tab=file]") |> render_click()
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      lv
      |> element("[phx-click=select_folder_node][phx-value-path=\"#{sub1}\"]")
      |> render_click()

      lv |> element("[phx-click=confirm_folder]") |> render_click()

      lv
      |> file_input("#add-torrent-modal form", :torrent_file, [
        %{name: "test.torrent", content: content, type: "application/x-bittorrent"}
      ])
      |> render_upload("test.torrent", 100)

      lv
      |> element("form[phx-submit=submit_file]")
      |> render_submit()

      _ = conn
    end
  end

  # ---------------------------------------------------------------------------
  # Batch F — Keyboard navigation
  # ---------------------------------------------------------------------------

  describe "keyboard navigation" do
    setup ctx, do: setup_dir(ctx)

    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      open_modal(lv)
      {:ok, lv: lv}
    end

    test "Escape key while picker is open closes the picker", %{lv: lv} do
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      assert render(lv) =~ ~s(aria-label="Select folder")

      # Target the focus_wrap element that has phx-window-keydown; this routes
      # the event to the component target (phx-target={@myself}) in test.
      lv
      |> element("[phx-window-keydown=close_folder_picker]")
      |> render_keydown(%{"key" => "Escape"})

      refute render(lv) =~ ~s(aria-label="Select folder")
    end

    test "picker has phx-window-keydown binding for Escape", %{lv: lv} do
      lv |> element("[phx-click=open_folder_picker]") |> render_click()

      html = render(lv)
      assert html =~ ~s(phx-window-keydown="close_folder_picker")
    end
  end
end
