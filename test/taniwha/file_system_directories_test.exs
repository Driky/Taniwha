defmodule Taniwha.FileSystemDirectoriesTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Taniwha.FileSystem

  # ---------------------------------------------------------------------------
  # Shared setup: temporary base directory
  # ---------------------------------------------------------------------------

  setup do
    base_dir =
      Path.join(System.tmp_dir!(), "taniwha_dirs_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(base_dir)
    on_exit(fn -> File.rm_rf!(base_dir) end)
    {:ok, base_dir: base_dir}
  end

  # ---------------------------------------------------------------------------
  # list_directories/2 — happy path
  # ---------------------------------------------------------------------------

  describe "list_directories/2 — happy path" do
    test "returns subdirectories sorted alphabetically", %{base_dir: base_dir} do
      for name <- ["zebra", "apple", "mango"] do
        File.mkdir_p!(Path.join(base_dir, name))
      end

      assert {:ok, entries} = FileSystem.list_directories(base_dir, base_dir)
      names = Enum.map(entries, & &1.name)
      assert names == ["apple", "mango", "zebra"]
    end

    test "returns empty list for directory with no subdirs", %{base_dir: base_dir} do
      File.write!(Path.join(base_dir, "file.txt"), "content")
      assert {:ok, []} = FileSystem.list_directories(base_dir, base_dir)
    end

    test "has_children: true for dirs that contain subdirectories", %{base_dir: base_dir} do
      parent = Path.join(base_dir, "parent")
      child = Path.join(parent, "child")
      grandchild = Path.join(child, "grandchild")
      File.mkdir_p!(grandchild)

      assert {:ok, entries} = FileSystem.list_directories(base_dir, base_dir)
      parent_entry = Enum.find(entries, &(&1.name == "parent"))
      assert parent_entry.has_children == true
    end

    test "has_children: false for empty leaf directories", %{base_dir: base_dir} do
      parent = Path.join(base_dir, "parent")
      leaf = Path.join(parent, "leaf")
      File.mkdir_p!(leaf)

      assert {:ok, entries} = FileSystem.list_directories(base_dir, base_dir)
      parent_entry = Enum.find(entries, &(&1.name == "parent"))
      # parent itself is listed with has_children true (it has leaf)
      assert parent_entry.has_children == true

      # Now list inside parent — leaf has no subdirs
      assert {:ok, leaf_entries} = FileSystem.list_directories(parent, base_dir)
      leaf_entry = Enum.find(leaf_entries, &(&1.name == "leaf"))
      assert leaf_entry.has_children == false
    end

    test "allows listing base_dir itself", %{base_dir: base_dir} do
      File.mkdir_p!(Path.join(base_dir, "sub"))
      assert {:ok, [%{name: "sub"}]} = FileSystem.list_directories(base_dir, base_dir)
    end

    test "each entry includes :name, :path, :has_children keys", %{base_dir: base_dir} do
      File.mkdir_p!(Path.join(base_dir, "mydir"))

      assert {:ok, [entry]} = FileSystem.list_directories(base_dir, base_dir)
      assert Map.has_key?(entry, :name)
      assert Map.has_key?(entry, :path)
      assert Map.has_key?(entry, :has_children)
      assert entry.path == Path.join(base_dir, "mydir")
    end
  end

  # ---------------------------------------------------------------------------
  # list_directories/2 — path traversal protection
  # ---------------------------------------------------------------------------

  describe "list_directories/2 — path traversal protection" do
    test "rejects path outside base_dir", %{base_dir: base_dir} do
      parent = Path.dirname(base_dir)

      assert {:error, {:path_outside_downloads_dir, resolved, configured}} =
               FileSystem.list_directories(parent, base_dir)

      assert resolved == Path.expand(parent)
      assert configured == Path.expand(base_dir)
    end

    test "rejects .. traversal escaping base_dir", %{base_dir: base_dir} do
      traversal = Path.join([base_dir, "..", "..", "..", "etc"])

      assert {:error, {:path_outside_downloads_dir, resolved, configured}} =
               FileSystem.list_directories(traversal, base_dir)

      assert is_binary(resolved)
      assert configured == Path.expand(base_dir)
    end

    test "rejects empty string path", %{base_dir: base_dir} do
      assert {:error, :invalid_path} = FileSystem.list_directories("", base_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # list_directories/2 — filesystem errors
  # ---------------------------------------------------------------------------

  describe "list_directories/2 — filesystem errors" do
    test "returns {:error, :enoent} for non-existent path", %{base_dir: base_dir} do
      missing = Path.join(base_dir, "does_not_exist")
      assert {:error, :enoent} = FileSystem.list_directories(missing, base_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # list_directories/2 — symlink handling
  # ---------------------------------------------------------------------------

  describe "list_directories/2 — symlink handling" do
    test "skips symlinks (not followed)", %{base_dir: base_dir} do
      real_dir = Path.join(base_dir, "real")
      File.mkdir_p!(real_dir)

      # Create a symlink inside base_dir pointing to an outside directory
      outside_dir =
        Path.join(
          System.tmp_dir!(),
          "taniwha_outside_#{:erlang.unique_integer([:positive])}"
        )

      File.mkdir_p!(outside_dir)
      on_exit(fn -> File.rm_rf!(outside_dir) end)

      symlink = Path.join(base_dir, "symlinked")
      File.ln_s!(outside_dir, symlink)

      # The symlink should not appear in results
      assert {:ok, entries} = FileSystem.list_directories(base_dir, base_dir)
      names = Enum.map(entries, & &1.name)
      assert "real" in names
      refute "symlinked" in names
    end
  end

  # ---------------------------------------------------------------------------
  # default_download_dir/0
  # ---------------------------------------------------------------------------

  describe "default_download_dir/0" do
    test "returns nil when downloads_dir is not configured" do
      original = Application.get_env(:taniwha, :downloads_dir)
      Application.delete_env(:taniwha, :downloads_dir)
      on_exit(fn -> Application.put_env(:taniwha, :downloads_dir, original) end)

      assert FileSystem.default_download_dir() == nil
    end

    test "returns configured value when downloads_dir is set" do
      Application.put_env(:taniwha, :downloads_dir, "/configured/path")
      on_exit(fn -> Application.delete_env(:taniwha, :downloads_dir) end)

      assert FileSystem.default_download_dir() == "/configured/path"
    end
  end
end
