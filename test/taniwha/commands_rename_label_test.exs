defmodule Taniwha.Commands.RenameLabelTest do
  # Not async — reads/writes the shared ETS store.
  use ExUnit.Case, async: false

  import Mox

  alias Taniwha.Commands
  alias Taniwha.State.Store
  alias Taniwha.Test.Fixtures

  setup :verify_on_exit!

  setup do
    Store.clear()
    on_exit(fn -> Store.clear() end)
    :ok
  end

  # ── Batch B1: rename_label/2 ──────────────────────────────────────────────

  describe "rename_label/2" do
    test "returns {:ok, 0} when no torrents have the label" do
      assert {:ok, 0} = Commands.rename_label("Movies", "Films")
    end

    test "renames label on a single matching torrent" do
      torrent = %{Fixtures.torrent_fixture("hash1") | label: "Movies"}
      Store.put_torrent(torrent)

      expect(Taniwha.RPC.MockClient, :call, fn "d.custom1.set", ["hash1", "Films"] ->
        {:ok, 0}
      end)

      assert {:ok, 1} = Commands.rename_label("Movies", "Films")
    end

    test "renames label on multiple matching torrents" do
      t1 = %{Fixtures.torrent_fixture("hash1") | label: "Movies"}
      t2 = %{Fixtures.torrent_fixture("hash2") | label: "Movies"}
      t3 = %{Fixtures.torrent_fixture("hash3") | label: "Linux"}
      Enum.each([t1, t2, t3], &Store.put_torrent/1)

      # Only the 2 "Movies" torrents get renamed
      expect(Taniwha.RPC.MockClient, :call, 2, fn "d.custom1.set", [_hash, "Films"] ->
        {:ok, 0}
      end)

      assert {:ok, 2} = Commands.rename_label("Movies", "Films")
    end

    test "does not touch torrents with a different label" do
      torrent = %{Fixtures.torrent_fixture("hash1") | label: "Linux"}
      Store.put_torrent(torrent)

      # No RPC calls expected
      assert {:ok, 0} = Commands.rename_label("Movies", "Films")
    end

    test "does not touch torrents with no label" do
      torrent = Fixtures.torrent_fixture("hash1")
      Store.put_torrent(torrent)

      assert {:ok, 0} = Commands.rename_label("Movies", "Films")
    end

    test "returns {:error, {ok, fail}} on partial failure" do
      t1 = %{Fixtures.torrent_fixture("hash1") | label: "Movies"}
      t2 = %{Fixtures.torrent_fixture("hash2") | label: "Movies"}
      Enum.each([t1, t2], &Store.put_torrent/1)

      # First call succeeds, second fails
      expect(Taniwha.RPC.MockClient, :call, fn "d.custom1.set", [hash, "Films"] ->
        if hash == "hash1", do: {:ok, 0}, else: {:error, :timeout}
      end)

      expect(Taniwha.RPC.MockClient, :call, fn "d.custom1.set", [hash, "Films"] ->
        if hash == "hash2", do: {:error, :timeout}, else: {:ok, 0}
      end)

      assert {:error, {1, 1}} = Commands.rename_label("Movies", "Films")
    end
  end
end
