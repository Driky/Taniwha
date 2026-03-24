defmodule TaniwhaWeb.FormatHelpers do
  @moduledoc """
  Human-readable formatting helpers for torrent data.

  All functions are pure and side-effect free. Import this module wherever
  you need to display torrent sizes, speeds, ratios, or ETAs.

  ## Examples

      iex> TaniwhaWeb.FormatHelpers.format_bytes(1_572_864)
      "1.5 MB"

      iex> TaniwhaWeb.FormatHelpers.format_speed(1_572_864)
      "1.50 MB/s"

      iex> TaniwhaWeb.FormatHelpers.format_ratio(1.5)
      "1.50"

      iex> TaniwhaWeb.FormatHelpers.format_eta(3_723)
      "1:02:03"
  """

  @doc """
  Formats a byte count as a human-readable string.

  Returns B for values below 1 KB, KB (1 decimal) below 1 MB,
  MB (1 decimal) below 1 GB, and GB (2 decimals) otherwise.

  ## Examples

      iex> format_bytes(0)
      "0 B"
      iex> format_bytes(1_024)
      "1.0 KB"
      iex> format_bytes(1_048_576)
      "1.0 MB"
      iex> format_bytes(1_073_741_824)
      "1.00 GB"
  """
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"

  def format_bytes(bytes) when bytes < 1_048_576 do
    :erlang.float_to_binary(bytes / 1_024, decimals: 1) <> " KB"
  end

  def format_bytes(bytes) when bytes < 1_073_741_824 do
    :erlang.float_to_binary(bytes / 1_048_576, decimals: 1) <> " MB"
  end

  def format_bytes(bytes) do
    :erlang.float_to_binary(bytes / 1_073_741_824, decimals: 2) <> " GB"
  end

  @doc """
  Formats a bytes-per-second value as a human-readable speed string.

  Returns B/s for values below 1 KB/s, KB/s (1 decimal) below 1 MB/s,
  MB/s (2 decimals) below 1 GB/s, and GB/s (2 decimals) otherwise.

  ## Examples

      iex> format_speed(0)
      "0 B/s"
      iex> format_speed(2_048)
      "2.0 KB/s"
      iex> format_speed(1_572_864)
      "1.50 MB/s"
  """
  @spec format_speed(non_neg_integer()) :: String.t()
  def format_speed(bytes) when bytes < 1_024, do: "#{bytes} B/s"

  def format_speed(bytes) when bytes < 1_048_576 do
    :erlang.float_to_binary(bytes / 1_024, decimals: 1) <> " KB/s"
  end

  def format_speed(bytes) when bytes < 1_073_741_824 do
    :erlang.float_to_binary(bytes / 1_048_576, decimals: 2) <> " MB/s"
  end

  def format_speed(bytes) do
    :erlang.float_to_binary(bytes / 1_073_741_824, decimals: 2) <> " GB/s"
  end

  @doc """
  Formats a ratio float to 2 decimal places.

  ## Examples

      iex> format_ratio(0.0)
      "0.00"
      iex> format_ratio(1.5)
      "1.50"
  """
  @spec format_ratio(float()) :: String.t()
  def format_ratio(ratio) do
    :erlang.float_to_binary(ratio, decimals: 2)
  end

  @doc """
  Formats a remaining-time value (in seconds) as a human-readable string.

  - `nil` or `:infinity` → `"∞"`
  - `<= 0` → `"Done"`
  - `< 3600` → `"M:SS"` (e.g. `"1:05"`)
  - `>= 3600` → `"H:MM:SS"` (e.g. `"1:02:03"`)

  ## Examples

      iex> format_eta(nil)
      "∞"
      iex> format_eta(0)
      "Done"
      iex> format_eta(65)
      "1:05"
      iex> format_eta(3_723)
      "1:02:03"
  """
  @doc """
  Formats an error reason from a torrent add operation as a user-facing string.

  ## Examples

      iex> format_add_error(:timeout)
      "Connection timed out. Is rtorrent running?"
      iex> format_add_error(:connection_refused)
      "Could not connect to rtorrent."
      iex> format_add_error(:something_else)
      "Failed to add torrent. Please try again."
  """
  @spec format_add_error(term()) :: String.t()
  def format_add_error(:timeout), do: "Connection timed out. Is rtorrent running?"
  def format_add_error(:connection_refused), do: "Could not connect to rtorrent."
  def format_add_error(_), do: "Failed to add torrent. Please try again."

  @spec format_eta(non_neg_integer() | nil | :infinity) :: String.t()
  def format_eta(nil), do: "∞"
  def format_eta(:infinity), do: "∞"
  def format_eta(seconds) when seconds <= 0, do: "Done"

  def format_eta(seconds) when seconds < 3_600 do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "#{m}:#{String.pad_leading(Integer.to_string(s), 2, "0")}"
  end

  def format_eta(seconds) do
    h = div(seconds, 3_600)
    remaining = rem(seconds, 3_600)
    m = div(remaining, 60)
    s = rem(remaining, 60)

    "#{h}:#{String.pad_leading(Integer.to_string(m), 2, "0")}:#{String.pad_leading(Integer.to_string(s), 2, "0")}"
  end
end
