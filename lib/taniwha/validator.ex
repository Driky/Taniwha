defmodule Taniwha.Validator do
  @moduledoc """
  Pure input validation for API boundaries.

  Used by channels, LiveView event handlers, and REST controllers to reject
  malformed inputs before they reach the `Taniwha.Commands` layer.
  """

  @hash_regex ~r/^[0-9a-fA-F]{40}$/

  @doc """
  Validates that a torrent hash is a 40-character hexadecimal string.
  """
  @spec validate_hash(term()) :: :ok | {:error, :invalid_hash}
  def validate_hash(hash) when is_binary(hash) do
    if Regex.match?(@hash_regex, hash), do: :ok, else: {:error, :invalid_hash}
  end

  def validate_hash(_), do: {:error, :invalid_hash}

  @doc """
  Validates that a file priority is one of the accepted values: 0 (off), 1 (normal), 2 (high).
  """
  @spec validate_priority(term()) :: :ok | {:error, :invalid_priority}
  def validate_priority(p) when p in [0, 1, 2], do: :ok
  def validate_priority(_), do: {:error, :invalid_priority}

  @doc """
  Validates that a URL is a magnet link or an HTTP/HTTPS URL.
  """
  @spec validate_url(term()) :: :ok | {:error, :invalid_url}
  def validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "magnet"} ->
        :ok

      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, :invalid_url}
    end
  end

  def validate_url(_), do: {:error, :invalid_url}
end
