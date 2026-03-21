defmodule Taniwha.State.StoreTest do
  use ExUnit.Case, async: false

  alias Taniwha.State.Store
  alias Taniwha.Torrent

  setup do
    Store.clear()
    :ok
  end

  defp build_torrent(hash, overrides \\ %{}) do
    struct!(Torrent, Map.merge(%{hash: hash, name: "Test Torrent"}, overrides))
  end

  # ── Batch 1: put_torrent / get_torrent ────────────────────────────────────

  describe "put_torrent/1 and get_torrent/1" do
    test "stores a torrent and retrieves it by hash" do
      torrent = build_torrent("hash1")
      assert :ok = Store.put_torrent(torrent)
      assert {:ok, ^torrent} = Store.get_torrent("hash1")
    end

    test "returns {:error, :not_found} for unknown hash" do
      assert {:error, :not_found} = Store.get_torrent("nonexistent")
    end
  end

  # ── Batch 2: get_all_torrents / count ────────────────────────────────────

  describe "get_all_torrents/0" do
    test "returns all stored torrents regardless of insertion order" do
      t1 = build_torrent("hash1")
      t2 = build_torrent("hash2")
      Store.put_torrent(t1)
      Store.put_torrent(t2)

      result = Store.get_all_torrents()
      hashes = result |> Enum.map(& &1.hash) |> Enum.sort()
      assert hashes == ["hash1", "hash2"]
    end

    test "returns empty list when store is empty" do
      assert Store.get_all_torrents() == []
    end
  end

  describe "count/0" do
    test "returns 0 when empty" do
      assert Store.count() == 0
    end

    test "returns the correct count after inserts" do
      Store.put_torrent(build_torrent("h1"))
      Store.put_torrent(build_torrent("h2"))
      Store.put_torrent(build_torrent("h3"))
      assert Store.count() == 3
    end
  end

  # ── Batch 3: upsert and delete_torrent ───────────────────────────────────

  describe "put_torrent/1 upsert" do
    test "updating an existing hash replaces the torrent" do
      original = build_torrent("hash1", %{name: "Original"})
      updated = build_torrent("hash1", %{name: "Updated"})

      Store.put_torrent(original)
      Store.put_torrent(updated)

      assert {:ok, fetched} = Store.get_torrent("hash1")
      assert fetched.name == "Updated"
      assert Store.count() == 1
    end
  end

  describe "delete_torrent/1" do
    test "removes a torrent by hash" do
      Store.put_torrent(build_torrent("hash1"))
      assert :ok = Store.delete_torrent("hash1")
      assert {:error, :not_found} = Store.get_torrent("hash1")
    end

    test "is a no-op for an unknown hash" do
      assert :ok = Store.delete_torrent("nonexistent")
    end
  end

  # ── Batch 4: clear / concurrent reads ────────────────────────────────────

  describe "clear/0" do
    test "empties the table" do
      Store.put_torrent(build_torrent("h1"))
      Store.put_torrent(build_torrent("h2"))
      assert Store.count() == 2

      assert :ok = Store.clear()
      assert Store.count() == 0
      assert Store.get_all_torrents() == []
    end
  end

  describe "concurrent reads" do
    test "50 concurrent readers do not crash and all see consistent data" do
      for i <- 1..10, do: Store.put_torrent(build_torrent("hash_#{i}"))

      all_ok =
        1..50
        |> Task.async_stream(fn _ -> Store.get_all_torrents() end, max_concurrency: 50)
        |> Enum.all?(fn {:ok, list} -> length(list) == 10 end)

      assert all_ok
    end
  end

  # ── Batch 5: table ownership stability ───────────────────────────────────

  describe "table ownership stability" do
    test "table persists across sequential operations" do
      Store.put_torrent(build_torrent("a"))
      assert Store.count() == 1

      Store.put_torrent(build_torrent("b"))
      assert Store.count() == 2

      Store.delete_torrent("a")
      assert Store.count() == 1

      assert {:ok, _} = Store.get_torrent("b")
    end
  end
end
