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
    test "fetches base_path, deletes within downloads_dir, then erases" do
      with_downloads_dir(fn dir ->
        torrent_path = Path.join(dir, "my_torrent")

        expect(Taniwha.RPC.MockClient, :call, fn "d.base_path", ["abc123"] ->
          {:ok, torrent_path}
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

    test "returns error when base_path is empty string" do
      with_downloads_dir(fn _dir ->
        expect(Taniwha.RPC.MockClient, :call, fn "d.base_path", ["abc123"] ->
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
    test "returns error when path outside downloads_dir, does NOT call d.erase" do
      with_downloads_dir(fn _dir ->
        expect(Taniwha.RPC.MockClient, :call, fn "d.base_path", ["abc123"] ->
          # Path clearly outside any reasonable downloads_dir
          {:ok, "/totally/different/path/file.txt"}
        end)

        # d.erase is NOT expected — unexpected call would fail the test
        assert {:error, {:path_outside_downloads_dir, _path, _dir}} =
                 Commands.erase_with_data("abc123")
      end)
    end

    test "d.erase is only called AFTER successful safe_delete" do
      # Verify ordering: base_path fetch, then safe_delete (implicit), then erase
      with_downloads_dir(fn dir ->
        torrent_path = Path.join(dir, "ordered_torrent")
        call_order = :ets.new(:call_order, [:bag, :public])

        expect(Taniwha.RPC.MockClient, :call, fn "d.base_path", ["hash_order"] ->
          :ets.insert(call_order, {:step, :base_path})
          {:ok, torrent_path}
        end)

        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["hash_order"] ->
          :ets.insert(call_order, {:step, :erase})
          {:ok, 0}
        end)

        assert :ok = Commands.erase_with_data("hash_order")

        steps = :ets.tab2list(call_order) |> Enum.map(&elem(&1, 1))
        assert steps == [:base_path, :erase]
        :ets.delete(call_order)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # erase_many/1 — Batch 4
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
  # erase_many_with_data/1 — Batch 5
  # ---------------------------------------------------------------------------

  describe "erase_many_with_data/1" do
    test "calls erase_with_data for each hash, returns ok/error split" do
      with_downloads_dir(fn dir ->
        path1 = Path.join(dir, "torrent1")
        path2 = Path.join(dir, "torrent2")

        expect(Taniwha.RPC.MockClient, :call, fn "d.base_path", ["h1"] -> {:ok, path1} end)
        expect(Taniwha.RPC.MockClient, :call, fn "d.erase", ["h1"] -> {:ok, 0} end)
        expect(Taniwha.RPC.MockClient, :call, fn "d.base_path", ["h2"] -> {:ok, path2} end)
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
