defmodule Taniwha.FileSystemTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Taniwha.FileSystem

  describe "safe_delete/2 — valid deletions" do
    setup do
      base_dir =
        Path.join(System.tmp_dir!(), "taniwha_fs_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(base_dir)
      on_exit(fn -> File.rm_rf!(base_dir) end)
      {:ok, base_dir: base_dir}
    end

    test "deletes a file within base_dir", %{base_dir: base_dir} do
      file = Path.join(base_dir, "file.txt")
      File.write!(file, "content")
      assert :ok = FileSystem.safe_delete(file, base_dir)
      refute File.exists?(file)
    end

    test "deletes a directory within base_dir", %{base_dir: base_dir} do
      dir = Path.join(base_dir, "subdir")
      inner = Path.join(dir, "inner.txt")
      File.mkdir_p!(dir)
      File.write!(inner, "x")
      assert :ok = FileSystem.safe_delete(dir, base_dir)
      refute File.exists?(dir)
    end

    test "non-existent path within base_dir returns :ok (idempotent)", %{base_dir: base_dir} do
      missing = Path.join(base_dir, "nonexistent.txt")
      assert :ok = FileSystem.safe_delete(missing, base_dir)
    end
  end

  describe "safe_delete/2 — path traversal protection" do
    setup do
      base_dir =
        Path.join(System.tmp_dir!(), "taniwha_fs_test_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(base_dir)
      on_exit(fn -> File.rm_rf!(base_dir) end)
      {:ok, base_dir: base_dir}
    end

    test "rejects path with .. traversal that escapes base_dir", %{base_dir: base_dir} do
      # e.g. /data/downloads/../../../etc/passwd
      traversal = Path.join([base_dir, "..", "..", "etc", "passwd"])
      assert {:error, :path_outside_downloads_dir} = FileSystem.safe_delete(traversal, base_dir)
    end

    test "rejects path equal to base_dir (never delete the root)", %{base_dir: base_dir} do
      assert {:error, :path_outside_downloads_dir} = FileSystem.safe_delete(base_dir, base_dir)
    end

    test "rejects path outside base_dir entirely", %{base_dir: base_dir} do
      other = Path.join(System.tmp_dir!(), "completely_other_file.txt")
      assert {:error, :path_outside_downloads_dir} = FileSystem.safe_delete(other, base_dir)
    end

    test "rejects path that shares prefix but is sibling of base_dir" do
      # /data/downloads and /data/downloads2 must not match
      uniq = :erlang.unique_integer([:positive])
      base = Path.join(System.tmp_dir!(), "taniwha_base_#{uniq}")
      sibling = base <> "2"
      File.mkdir_p!(sibling)
      target = Path.join(sibling, "file.txt")
      File.write!(target, "x")
      on_exit(fn -> File.rm_rf!(sibling) end)

      assert {:error, :path_outside_downloads_dir} = FileSystem.safe_delete(target, base)
    end
  end

  describe "safe_delete/2 — invalid input" do
    test "rejects empty path" do
      assert {:error, :invalid_path} = FileSystem.safe_delete("", "/some/dir")
    end
  end
end
