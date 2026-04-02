defmodule Taniwha.CommandsRemoveTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mox

  alias Taniwha.Commands

  setup :verify_on_exit!

  # ---------------------------------------------------------------------------
  # Helper: create a fresh temp dir as the downloads_dir for each test
  # ---------------------------------------------------------------------------

  defp with_downloads_dir(fun) do
    dir =
      Path.join(System.tmp_dir!(), "taniwha_dl_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    Application.put_env(:taniwha, :downloads_dir, dir)

    try do
      fun.(dir)
    after
      Application.delete_env(:taniwha, :downloads_dir)
      File.rm_rf!(dir)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_with_data/1 — Batch 1: happy paths
  # ---------------------------------------------------------------------------

  describe "erase_with_data/1 — happy path" do
    test "fetches directory + file list, deletes within downloads_dir, then erases" do
      with_downloads_dir(fn dir ->
        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["abc123"] ->
          {:ok, dir}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["abc123", "" | ["f.path="]] ->
          {:ok, [["my_torrent_file.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["abc123"] ->
          {:ok, 0}
        end)

        assert :ok = Commands.erase_with_data("abc123")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_with_data/1 — Batch 2: configuration errors
  # ---------------------------------------------------------------------------

  describe "erase_with_data/1 — configuration errors" do
    test "returns error when downloads_dir not configured" do
      Application.delete_env(:taniwha, :downloads_dir)
      # No RPC calls should be made
      assert {:error, :downloads_dir_not_configured} = Commands.erase_with_data("abc123")
    end

    test "returns error when directory is empty string" do
      with_downloads_dir(fn _dir ->
        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["abc123"] ->
          {:ok, ""}
        end)

        # d.erase is NOT called
        assert {:error, :no_base_path} = Commands.erase_with_data("abc123")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_with_data/1 — Batch 3: path validation prevents erase
  # ---------------------------------------------------------------------------

  describe "erase_with_data/1 — path validation" do
    test "returns error when file path is outside downloads_dir, does NOT call d.erase" do
      with_downloads_dir(fn _dir ->
        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["abc123"] ->
          # Directory clearly outside any reasonable downloads_dir
          {:ok, "/totally/different/path"}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["abc123", "" | ["f.path="]] ->
          {:ok, [["file.txt"]]}
        end)

        # d.erase is NOT expected — unexpected call would fail the test
        assert {:error, {:path_outside_downloads_dir, _path, _dir}} =
                 Commands.erase_with_data("abc123")
      end)
    end

    test "d.erase is only called AFTER successful file deletion" do
      # Verify ordering: directory fetch, file list, safe_delete (implicit), then erase
      with_downloads_dir(fn dir ->
        call_order = :ets.new(:call_order, [:bag, :public])

        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["hash_order"] ->
          :ets.insert(call_order, {:step, :directory})
          {:ok, dir}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall",
                                                 ["hash_order", "" | ["f.path="]] ->
          :ets.insert(call_order, {:step, :multicall})
          {:ok, [["ordered_file.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["hash_order"] ->
          :ets.insert(call_order, {:step, :erase})
          {:ok, 0}
        end)

        assert :ok = Commands.erase_with_data("hash_order")

        steps = :ets.tab2list(call_order) |> Enum.map(&elem(&1, 1))
        assert steps == [:directory, :multicall, :erase]
        :ets.delete(call_order)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_with_data/1 — Batch 4: flat multi-file regression (the bug)
  # ---------------------------------------------------------------------------

  describe "erase_with_data/1 — flat multi-file torrent (regression)" do
    test "deletes individual files, leaves parent directory intact" do
      with_downloads_dir(fn dir ->
        # Files placed directly in dir — no sub-folder (flat multi-file torrent)
        file1 = Path.join(dir, "episode.s01e01.mkv")
        file2 = Path.join(dir, "episode.s01e02.mkv")
        File.write!(file1, "data")
        File.write!(file2, "data")

        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["flat"] ->
          {:ok, dir}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["flat", "" | ["f.path="]] ->
          {:ok, [["episode.s01e01.mkv"], ["episode.s01e02.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["flat"] -> {:ok, 0} end)

        assert :ok = Commands.erase_with_data("flat")
        refute File.exists?(file1)
        refute File.exists?(file2)
        # Parent directory must NOT be deleted
        assert File.dir?(dir)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_with_data/1 — Batch 5: single-file and sub-directory shapes
  # ---------------------------------------------------------------------------

  describe "erase_with_data/1 — torrent shapes" do
    test "single-file torrent: deletes only the one file" do
      with_downloads_dir(fn dir ->
        movie = Path.join(dir, "movie.mkv")
        File.write!(movie, "data")
        other = Path.join(dir, "other.mkv")
        File.write!(other, "data")

        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["single"] ->
          {:ok, dir}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["single", "" | ["f.path="]] ->
          {:ok, [["movie.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["single"] -> {:ok, 0} end)

        assert :ok = Commands.erase_with_data("single")
        refute File.exists?(movie)
        # sibling file untouched
        assert File.exists?(other)
      end)
    end

    test "multi-file with sub-dir: deletes files, empty sub-dir remains" do
      with_downloads_dir(fn dir ->
        show_dir = Path.join(dir, "MyShow")
        File.mkdir_p!(show_dir)
        ep1 = Path.join(show_dir, "ep1.mkv")
        ep2 = Path.join(show_dir, "ep2.mkv")
        File.write!(ep1, "data")
        File.write!(ep2, "data")

        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["subdir"] ->
          {:ok, dir}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["subdir", "" | ["f.path="]] ->
          {:ok, [["MyShow/ep1.mkv"], ["MyShow/ep2.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["subdir"] -> {:ok, 0} end)

        assert :ok = Commands.erase_with_data("subdir")
        refute File.exists?(ep1)
        refute File.exists?(ep2)
        # Empty sub-dir remains (we don't prune directories)
        assert File.dir?(show_dir)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_many/1 — Batch 6
  # ---------------------------------------------------------------------------

  describe "erase_many/1" do
    test "returns {:ok, ok_hashes, []} when all succeed" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h1"] -> {:ok, 0} end)
      expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h2"] -> {:ok, 0} end)

      assert {:ok, ok, []} = Commands.erase_many(["h1", "h2"])
      assert Enum.sort(ok) == ["h1", "h2"]
    end

    test "separates ok hashes from error hashes" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h1"] -> {:ok, 0} end)
      expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h2"] -> {:error, :rpc_error} end)

      assert {:ok, ["h1"], ["h2"]} = Commands.erase_many(["h1", "h2"])
    end

    test "returns {:ok, [], []} for empty list" do
      assert {:ok, [], []} = Commands.erase_many([])
    end
  end

  # ---------------------------------------------------------------------------
  # erase_many_with_data/1 — Batch 7
  # ---------------------------------------------------------------------------

  describe "erase_many_with_data/1" do
    test "calls erase_with_data for each hash, returns ok/error split" do
      with_downloads_dir(fn dir ->
        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["h1"] -> {:ok, dir} end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["h1", "" | ["f.path="]] ->
          {:ok, [["torrent1.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h1"] -> {:ok, 0} end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.directory", ["h2"] -> {:ok, dir} end)

        expect(Taniwha.RPC.MockClient, :call, fn "f.multicall", ["h2", "" | ["f.path="]] ->
          {:ok, [["torrent2.mkv"]]}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h2"] -> {:ok, 0} end)

        assert {:ok, ok, []} = Commands.erase_many_with_data(["h1", "h2"])
        assert Enum.sort(ok) == ["h1", "h2"]
      end)
    end

    test "returns {:ok, [], []} for empty list" do
      Application.delete_env(:taniwha, :downloads_dir)
      assert {:ok, [], []} = Commands.erase_many_with_data([])
    end
  end
end
