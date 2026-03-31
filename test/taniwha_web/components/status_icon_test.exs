defmodule TaniwhaWeb.StatusIconTest do
  use TaniwhaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TaniwhaWeb.TorrentComponents.StatusComponents

  describe "status_icon/1" do
    test "renders svg element" do
      html = render_component(&status_icon/1, status: :downloading)
      assert html =~ "<svg"
    end

    test ":seeding renders up-arrow path" do
      html = render_component(&status_icon/1, status: :seeding)
      assert html =~ "M5 10l7-7m0 0l7 7m-7-7v18"
    end

    test ":downloading renders down-arrow path" do
      html = render_component(&status_icon/1, status: :downloading)
      assert html =~ "M19 14l-7 7m0 0l-7-7m7 7V3"
    end

    test ":stopped renders rect element" do
      html = render_component(&status_icon/1, status: :stopped)
      assert html =~ "<rect"
    end

    test ":stopped uses fill currentColor (no stroke)" do
      html = render_component(&status_icon/1, status: :stopped)
      assert html =~ ~s(fill="currentColor")
      refute html =~ ~s(stroke="currentColor")
    end

    test ":paused renders pause circles path" do
      html = render_component(&status_icon/1, status: :paused)
      assert html =~ "M10 9v6m4-6v6"
    end

    test ":checking renders sync arrows path" do
      html = render_component(&status_icon/1, status: :checking)
      assert html =~ "M4 4v5h.582"
    end

    test ":unknown renders exclamation circle path" do
      html = render_component(&status_icon/1, status: :unknown)
      assert html =~ "M12 9v3.75m9-.75"
    end

    test ":seeding has aria-label=Seeding" do
      html = render_component(&status_icon/1, status: :seeding)
      assert html =~ ~s(aria-label="Seeding")
    end

    test ":downloading has aria-label=Downloading" do
      html = render_component(&status_icon/1, status: :downloading)
      assert html =~ ~s(aria-label="Downloading")
    end

    test ":stopped has aria-label=Stopped" do
      html = render_component(&status_icon/1, status: :stopped)
      assert html =~ ~s(aria-label="Stopped")
    end

    test ":paused has aria-label=Paused" do
      html = render_component(&status_icon/1, status: :paused)
      assert html =~ ~s(aria-label="Paused")
    end

    test ":checking has aria-label=Checking" do
      html = render_component(&status_icon/1, status: :checking)
      assert html =~ ~s(aria-label="Checking")
    end

    test ":unknown has aria-label=Unknown" do
      html = render_component(&status_icon/1, status: :unknown)
      assert html =~ ~s(aria-label="Unknown")
    end

    test "each status has role=img on wrapper" do
      for status <- [:seeding, :downloading, :stopped, :paused, :checking, :unknown] do
        html = render_component(&status_icon/1, status: status)
        assert html =~ ~s(role="img"), "Expected role=img for status #{status}"
      end
    end

    test "non-stopped statuses use stroke currentColor" do
      for status <- [:seeding, :downloading, :paused, :checking, :unknown] do
        html = render_component(&status_icon/1, status: status)

        assert html =~ ~s(stroke="currentColor"),
               "Expected stroke=currentColor for status #{status}"
      end
    end
  end
end
