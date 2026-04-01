defmodule Taniwha.FileSystem do
  @moduledoc """
  Filesystem helpers with path-traversal protection.

  The `safe_delete/2` function validates that a given path is strictly inside
  a configured base directory before delegating to `File.rm_rf/1`. This
  prevents path traversal attacks from reaching files outside the download
  directory. On rejection the error tuple includes both the resolved path and
  the configured directory to make volume-mount misconfigurations easier to
  diagnose.

  The `list_directories/2` function returns immediate subdirectories of a path,
  restricted to within `base_dir`. Symlinks are skipped (via `File.lstat/1`)
  to prevent escaping the base directory through symlink traversal.
  """

  @doc """
  Deletes `path` (file or directory) only if it is strictly inside `base_dir`.

  Returns `:ok` if the deletion succeeded (including when the path does not
  exist — `File.rm_rf/1` is idempotent). Returns one of the following errors:

    * `{:error, :invalid_path}` — path is an empty string
    * `{:error, {:path_outside_downloads_dir, resolved_path, configured_dir}}` —
      resolved path is not inside `base_dir`, or is `base_dir` itself. Both
      `resolved_path` and `configured_dir` are absolute, expanded strings to aid
      debugging misconfigured volume mounts.
    * `{:error, posix}` — a POSIX error from `File.rm_rf/1` (e.g. `:eacces`)

  ## Security notes

  `Path.expand/1` resolves `..` components before the prefix check, preventing
  directory traversal attacks. Appending `"/"` to both the resolved path and
  the base prevents `/data/downloads2` from matching base `/data/downloads`.
  The path is never allowed to equal `base_dir` itself.
  """
  @spec safe_delete(String.t(), String.t()) ::
          :ok
          | {:error,
             :invalid_path
             | {:path_outside_downloads_dir, String.t(), String.t()}
             | File.posix()}
  def safe_delete("", _base_dir), do: {:error, :invalid_path}

  def safe_delete(path, base_dir) do
    resolved = Path.expand(path)
    expanded_base = Path.expand(base_dir)

    if resolved == expanded_base or not within_base_dir?(resolved, expanded_base) do
      {:error, {:path_outside_downloads_dir, resolved, expanded_base}}
    else
      File.rm_rf(resolved) |> normalize_rm_result()
    end
  end

  @doc """
  Lists immediate subdirectories of `path`, restricted to within `base_dir`.

  Returns `{:ok, entries}` where each entry is a map with:

    * `:name` — the directory name (basename only)
    * `:path` — the absolute path to the directory
    * `:has_children` — `true` if the directory contains at least one subdirectory

  Symlinks are skipped silently (uses `File.lstat/1`, which does not follow
  symlinks). Only entries of type `:directory` are included.

  Returns one of the following errors:

    * `{:error, :invalid_path}` — path is an empty string
    * `{:error, {:path_outside_downloads_dir, resolved_path, configured_dir}}` —
      resolved path is outside `base_dir`
    * `{:error, posix}` — a POSIX error from `File.ls/1` (e.g. `:enoent`, `:eacces`)

  ## Security notes

  `Path.expand/1` resolves `..` before the prefix check. `File.lstat/1` does
  not follow symlinks, so symlinks pointing outside `base_dir` are skipped.
  Listing `base_dir` itself is allowed (unlike `safe_delete/2`).
  """
  @spec list_directories(String.t(), String.t()) ::
          {:ok, [%{name: String.t(), path: String.t(), has_children: boolean()}]}
          | {:error,
             :invalid_path
             | {:path_outside_downloads_dir, String.t(), String.t()}
             | File.posix()}
  def list_directories("", _base_dir), do: {:error, :invalid_path}

  def list_directories(path, base_dir) do
    resolved = Path.expand(path)
    exp_base = Path.expand(base_dir)

    if within_base_dir?(resolved, exp_base) do
      case File.ls(resolved) do
        {:ok, names} ->
          entries =
            names
            |> Enum.sort()
            |> Enum.flat_map(fn name ->
              full = Path.join(resolved, name)

              case File.lstat(full) do
                {:ok, %{type: :directory}} ->
                  [%{name: name, path: full, has_children: has_subdirectories?(full)}]

                _ ->
                  []
              end
            end)

          {:ok, entries}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:path_outside_downloads_dir, resolved, exp_base}}
    end
  end

  @doc """
  Returns the configured downloads directory, or `nil` if not set.

  Reads `Application.get_env(:taniwha, :downloads_dir)`, which is populated
  from the `TANIWHA_DOWNLOADS_DIR` environment variable at runtime.
  """
  @spec default_download_dir() :: String.t() | nil
  def default_download_dir do
    Application.get_env(:taniwha, :downloads_dir)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec within_base_dir?(String.t(), String.t()) :: boolean()
  defp within_base_dir?(resolved, expanded_base) do
    String.starts_with?(resolved <> "/", expanded_base <> "/")
  end

  @spec has_subdirectories?(String.t()) :: boolean()
  defp has_subdirectories?(path) do
    case File.ls(path) do
      {:ok, names} ->
        Enum.any?(names, fn n ->
          match?({:ok, %{type: :directory}}, File.lstat(Path.join(path, n)))
        end)

      _ ->
        false
    end
  end

  @spec normalize_rm_result({:ok, [String.t()]} | {:error, File.posix(), String.t()}) ::
          :ok | {:error, File.posix()}
  defp normalize_rm_result({:ok, _}), do: :ok
  defp normalize_rm_result({:error, posix, _path}), do: {:error, posix}
end
