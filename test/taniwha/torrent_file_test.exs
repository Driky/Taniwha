defmodule Taniwha.TorrentFileTest do
  use ExUnit.Case, async: true

  alias Taniwha.TorrentFile

  # ---------------------------------------------------------------------------
  # Batch 1 — struct + progress/1
  # ---------------------------------------------------------------------------

  describe "struct" do
    test "creates a TorrentFile with given fields" do
      file = %TorrentFile{
        path: "/downloads/file.mkv",
        size: 1_000_000,
        completed_chunks: 500,
        total_chunks: 1000,
        priority: 1
      }

      assert file.path == "/downloads/file.mkv"
      assert file.size == 1_000_000
    end
  end

  describe "progress/1" do
    test "returns 0.0 when total_chunks is 0" do
      file = %TorrentFile{total_chunks: 0, completed_chunks: 0}
      assert TorrentFile.progress(file) == 0.0
    end

    test "returns 0.5 for half completed" do
      file = %TorrentFile{total_chunks: 100, completed_chunks: 50}
      assert TorrentFile.progress(file) == 0.5
    end

    test "returns 1.0 for fully completed" do
      file = %TorrentFile{total_chunks: 100, completed_chunks: 100}
      assert TorrentFile.progress(file) == 1.0
    end

    test "returns a float" do
      file = %TorrentFile{total_chunks: 3, completed_chunks: 1}
      assert is_float(TorrentFile.progress(file))
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — priority_label/1
  # ---------------------------------------------------------------------------

  describe "priority_label/1" do
    test "0 maps to :skip" do
      assert TorrentFile.priority_label(0) == :skip
    end

    test "1 maps to :normal" do
      assert TorrentFile.priority_label(1) == :normal
    end

    test "2 maps to :high" do
      assert TorrentFile.priority_label(2) == :high
    end
  end
end
