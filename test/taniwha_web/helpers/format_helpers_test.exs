defmodule TaniwhaWeb.FormatHelpersTest do
  use ExUnit.Case, async: true

  alias TaniwhaWeb.FormatHelpers

  # ---------------------------------------------------------------------------
  # Batch 1 — format_bytes/1
  # ---------------------------------------------------------------------------

  describe "format_bytes/1" do
    test "0 bytes renders as 0 B" do
      assert FormatHelpers.format_bytes(0) == "0 B"
    end

    test "1023 bytes renders as B (below 1 KB threshold)" do
      assert FormatHelpers.format_bytes(1_023) == "1023 B"
    end

    test "1024 bytes renders as 1.0 KB" do
      assert FormatHelpers.format_bytes(1_024) == "1.0 KB"
    end

    test "2048 bytes renders as 2.0 KB" do
      assert FormatHelpers.format_bytes(2_048) == "2.0 KB"
    end

    test "1048576 bytes (1 MB) renders as 1.0 MB" do
      assert FormatHelpers.format_bytes(1_048_576) == "1.0 MB"
    end

    test "1572864 bytes renders as 1.5 MB" do
      assert FormatHelpers.format_bytes(1_572_864) == "1.5 MB"
    end

    test "1073741824 bytes (1 GB) renders as 1.00 GB" do
      assert FormatHelpers.format_bytes(1_073_741_824) == "1.00 GB"
    end

    test "2147483648 bytes renders as 2.00 GB" do
      assert FormatHelpers.format_bytes(2_147_483_648) == "2.00 GB"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — format_speed/1
  # ---------------------------------------------------------------------------

  describe "format_speed/1" do
    test "0 bytes/s renders as 0 B/s" do
      assert FormatHelpers.format_speed(0) == "0 B/s"
    end

    test "512 bytes/s renders as B/s" do
      assert FormatHelpers.format_speed(512) == "512 B/s"
    end

    test "2048 bytes/s renders as 2.0 KB/s" do
      assert FormatHelpers.format_speed(2_048) == "2.0 KB/s"
    end

    test "1572864 bytes/s renders as 1.50 MB/s" do
      assert FormatHelpers.format_speed(1_572_864) == "1.50 MB/s"
    end

    test "2147483648 bytes/s renders as 2.00 GB/s" do
      assert FormatHelpers.format_speed(2_147_483_648) == "2.00 GB/s"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — format_ratio/1
  # ---------------------------------------------------------------------------

  describe "format_ratio/1" do
    test "0.0 renders as 0.00" do
      assert FormatHelpers.format_ratio(0.0) == "0.00"
    end

    test "1.5 renders as 1.50" do
      assert FormatHelpers.format_ratio(1.5) == "1.50"
    end

    test "2.333 rounds to 2 decimals" do
      assert FormatHelpers.format_ratio(2.333) == "2.33"
    end

    test "10.0 renders as 10.00" do
      assert FormatHelpers.format_ratio(10.0) == "10.00"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — format_eta/1
  # ---------------------------------------------------------------------------

  describe "format_eta/1" do
    test "nil renders as ∞" do
      assert FormatHelpers.format_eta(nil) == "∞"
    end

    test ":infinity renders as ∞" do
      assert FormatHelpers.format_eta(:infinity) == "∞"
    end

    test "0 seconds renders as Done" do
      assert FormatHelpers.format_eta(0) == "Done"
    end

    test "65 seconds renders as MM:SS format" do
      assert FormatHelpers.format_eta(65) == "1:05"
    end

    test "3600 seconds (1 hour) renders as H:MM:SS" do
      assert FormatHelpers.format_eta(3_600) == "1:00:00"
    end

    test "3723 seconds renders as 1:02:03" do
      assert FormatHelpers.format_eta(3_723) == "1:02:03"
    end

    test "59 seconds renders as 0:59" do
      assert FormatHelpers.format_eta(59) == "0:59"
    end

    test "negative seconds treated as done" do
      assert FormatHelpers.format_eta(-1) == "Done"
    end
  end
end
