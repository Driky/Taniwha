defmodule Taniwha.SCGI.ProtocolTest do
  use ExUnit.Case, async: true

  alias Taniwha.SCGI.Protocol

  # ---------------------------------------------------------------------------
  # Test helpers
  # ---------------------------------------------------------------------------

  defp extract_headers(encoded) do
    [netstring_part, _rest] = :binary.split(encoded, ",")
    [_len, headers] = :binary.split(netstring_part, ":")
    headers
  end

  defp parse_header_pairs(headers) do
    headers
    |> :binary.split(<<0>>, [:global])
    |> Enum.reject(&(&1 == ""))
    |> Enum.chunk_every(2)
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  # ---------------------------------------------------------------------------
  # Batch 1 — encode/1
  # ---------------------------------------------------------------------------

  describe "encode/1" do
    test "returns a binary" do
      result = Protocol.encode("body")
      assert is_binary(result)
    end

    test "starts with a valid netstring (digits:...,)" do
      encoded = Protocol.encode("hello")
      assert Regex.match?(~r/^\d+:/, encoded)
    end

    test "body is appended after the netstring comma" do
      body = "<?xml version='1.0'?>"
      encoded = Protocol.encode(body)
      [_netstring, body_part] = :binary.split(encoded, ",")
      assert body_part == body
    end

    test "CONTENT_LENGTH matches byte_size of body" do
      body = "some body"
      encoded = Protocol.encode(body)
      headers = extract_headers(encoded)
      pairs = parse_header_pairs(headers)
      assert pairs["CONTENT_LENGTH"] == Integer.to_string(byte_size(body))
    end

    test "CONTENT_LENGTH reflects byte_size for multi-byte UTF-8" do
      # "€" is 3 bytes in UTF-8; 3 × "€" = 9 bytes, not 3 chars
      body = "€€€"
      assert byte_size(body) == 9
      encoded = Protocol.encode(body)
      headers = extract_headers(encoded)
      pairs = parse_header_pairs(headers)
      assert pairs["CONTENT_LENGTH"] == "9"
    end

    test "headers contain SCGI=1" do
      encoded = Protocol.encode("body")
      headers = extract_headers(encoded)
      pairs = parse_header_pairs(headers)
      assert pairs["SCGI"] == "1"
    end

    test "headers contain REQUEST_METHOD=POST" do
      encoded = Protocol.encode("body")
      headers = extract_headers(encoded)
      pairs = parse_header_pairs(headers)
      assert pairs["REQUEST_METHOD"] == "POST"
    end

    test "headers contain REQUEST_URI=/RPC2" do
      encoded = Protocol.encode("body")
      headers = extract_headers(encoded)
      pairs = parse_header_pairs(headers)
      assert pairs["REQUEST_URI"] == "/RPC2"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — decode_response/1
  # ---------------------------------------------------------------------------

  describe "decode_response/1" do
    test "well-formed response returns {:ok, body}" do
      raw = "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n<xml/>"
      assert Protocol.decode_response(raw) == {:ok, "<xml/>"}
    end

    test "body containing embedded \\r\\n is extracted correctly" do
      body = "<xml>\r\n<item/>\r\n</xml>"
      raw = "Status: 200\r\n\r\n" <> body
      assert Protocol.decode_response(raw) == {:ok, body}
    end

    test "no blank line returns {:error, :invalid_response}" do
      raw = "Status: 200\r\nContent-Type: text/xml"
      assert Protocol.decode_response(raw) == {:error, :invalid_response}
    end

    test "empty binary returns {:error, :invalid_response}" do
      assert Protocol.decode_response("") == {:error, :invalid_response}
    end

    test "blank line at start (empty header block) returns {:ok, body}" do
      raw = "\r\n\r\nbody content"
      assert Protocol.decode_response(raw) == {:ok, "body content"}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — Structural integrity
  # ---------------------------------------------------------------------------

  describe "structural integrity" do
    test "netstring length prefix matches actual header byte_size" do
      encoded = Protocol.encode("some body")
      [netstring_part, _rest] = :binary.split(encoded, ",")
      [len_str, headers] = :binary.split(netstring_part, ":")
      assert String.to_integer(len_str) == byte_size(headers)
    end

    test "full frame structure: body is recoverable" do
      body = "<methodCall><methodName>system.listMethods</methodName></methodCall>"
      encoded = Protocol.encode(body)
      [_netstring, recovered_body] = :binary.split(encoded, ",")
      assert recovered_body == body
    end

    test "empty body encodes with CONTENT_LENGTH=0" do
      encoded = Protocol.encode("")
      headers = extract_headers(encoded)
      pairs = parse_header_pairs(headers)
      assert pairs["CONTENT_LENGTH"] == "0"
    end
  end
end
