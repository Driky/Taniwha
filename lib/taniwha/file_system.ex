defmodule Taniwha.FileSystem do
  @moduledoc """
  Filesystem helpers with path-traversal protection.

  The `safe_delete/2` function validates that a given path is strictly inside
  a configured base directory before delegating to `File.rm_rf/1`. This
  prevents path traversal attacks from reaching files outside the download
  directory. On rejection the error tuple includes both the resolved path and
  the configured directory to make volume-mount misconfigurations easier to
  diagnose.
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
    base_with_sep = expanded_base <> "/"
    resolved_with_sep = resolved <> "/"

    cond do
      resolved == expanded_base ->
        {:error, {:path_outside_downloads_dir, resolved, expanded_base}}

      not String.starts_with?(resolved_with_sep, base_with_sep) ->
        {:error, {:path_outside_downloads_dir, resolved, expanded_base}}

      true ->
        File.rm_rf(resolved) |> normalize_rm_result()
    end
  end

  @spec normalize_rm_result({:ok, [String.t()]} | {:error, File.posix(), String.t()}) ::
          :ok | {:error, File.posix()}
  defp normalize_rm_result({:ok, _}), do: :ok
  defp normalize_rm_result({:error, posix, _path}), do: {:error, posix}
end
