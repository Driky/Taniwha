defmodule Taniwha.Test.Fixtures do
  @moduledoc "Helpers for building sample data in tests: XML-RPC responses and struct fixtures."

  alias Taniwha.Torrent

  @fixtures_dir Path.join([__DIR__, "fixtures"])

  @doc """
  Builds a `Torrent` struct suitable for use in tests.

  Pass an optional hash to override the default. All other fields are set to
  representative values that exercise progress/status helpers.
  """
  @spec torrent_fixture(String.t()) :: Torrent.t()
  def torrent_fixture(hash \\ "abc123def456abc123def456abc123de") do
    %Torrent{
      hash: hash,
      name: "Test Torrent",
      size: 1_000_000,
      completed_bytes: 500_000,
      upload_rate: 100,
      download_rate: 200,
      ratio: 0.5,
      state: :started,
      is_active: true,
      complete: false,
      is_hash_checking: false,
      peers_connected: 5,
      started_at: nil,
      finished_at: nil,
      base_path: "/downloads/test"
    }
  end

  @doc "Returns the download_list XML fixture (3 info-hashes in an array)."
  def download_list_xml, do: File.read!(Path.join(@fixtures_dir, "download_list.xml"))

  @doc "Returns the torrent_name XML fixture (single string response)."
  def torrent_name_xml, do: File.read!(Path.join(@fixtures_dir, "torrent_name.xml"))

  @doc "Returns the multicall XML fixture (7-element multicall response)."
  def multicall_xml, do: File.read!(Path.join(@fixtures_dir, "multicall.xml"))

  @doc "Returns the fault XML fixture (fault with i4 code)."
  def fault_xml, do: File.read!(Path.join(@fixtures_dir, "fault.xml"))
end
