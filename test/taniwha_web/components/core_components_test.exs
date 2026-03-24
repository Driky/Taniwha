defmodule TaniwhaWeb.CoreComponentsTest do
  use TaniwhaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TaniwhaWeb.CoreComponents

  # ---------------------------------------------------------------------------
  # flash/1 — success variant
  # ---------------------------------------------------------------------------

  describe "flash/1 :success kind" do
    test "renders alert-success class" do
      html = render_component(&flash/1, kind: :success, flash: %{"success" => "All done"})
      assert html =~ "alert-success"
    end

    test "renders hero-check-circle icon" do
      html = render_component(&flash/1, kind: :success, flash: %{"success" => "All done"})
      assert html =~ "hero-check-circle"
    end

    test "renders the flash message" do
      html = render_component(&flash/1, kind: :success, flash: %{"success" => "Torrent added"})
      assert html =~ "Torrent added"
    end
  end

  # ---------------------------------------------------------------------------
  # flash_group/1 — success variant included
  # ---------------------------------------------------------------------------

  describe "flash_group/1" do
    test "renders success flash when present in flash map" do
      html =
        render_component(&TaniwhaWeb.Layouts.flash_group/1,
          flash: %{"success" => "Torrent added"},
          id: "flash-group-test"
        )

      assert html =~ "alert-success"
      assert html =~ "Torrent added"
    end
  end
end
