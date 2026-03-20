defmodule Taniwha.Test.Fixtures do
  @moduledoc "Helper to build sample XML-RPC response binaries for tests."

  @fixtures_dir Path.join([__DIR__, "fixtures"])

  @doc "Returns the download_list XML fixture (3 info-hashes in an array)."
  def download_list_xml, do: File.read!(Path.join(@fixtures_dir, "download_list.xml"))

  @doc "Returns the torrent_name XML fixture (single string response)."
  def torrent_name_xml, do: File.read!(Path.join(@fixtures_dir, "torrent_name.xml"))

  @doc "Returns the multicall XML fixture (7-element multicall response)."
  def multicall_xml, do: File.read!(Path.join(@fixtures_dir, "multicall.xml"))

  @doc "Returns the fault XML fixture (fault with i4 code)."
  def fault_xml, do: File.read!(Path.join(@fixtures_dir, "fault.xml"))
end
