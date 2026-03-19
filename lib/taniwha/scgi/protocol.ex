defmodule Taniwha.SCGI.Protocol do
  @moduledoc """
  SCGI framing encoder/decoder.

  Encodes an XML-RPC body as a valid SCGI request frame and decodes raw SCGI
  responses by stripping the HTTP-style header block.
  """

  @doc """
  Encodes `body` as an SCGI request frame.

  The frame layout is:

      <netstring-length>:<NUL-delimited headers>,<body>

  Fixed headers included:
  - `CONTENT_LENGTH` — `byte_size(body)` (raw byte count, not character count)
  - `SCGI` — `"1"`
  - `REQUEST_METHOD` — `"POST"`
  - `REQUEST_URI` — `"/RPC2"`
  """
  @spec encode(binary()) :: binary()
  def encode(body) when is_binary(body) do
    headers =
      "CONTENT_LENGTH" <>
        <<0>> <>
        Integer.to_string(byte_size(body)) <>
        <<0>> <>
        "SCGI" <>
        <<0>> <>
        "1" <>
        <<0>> <>
        "REQUEST_METHOD" <>
        <<0>> <>
        "POST" <>
        <<0>> <>
        "REQUEST_URI" <> <<0>> <> "/RPC2" <> <<0>>

    Integer.to_string(byte_size(headers)) <> ":" <> headers <> "," <> body
  end

  @doc """
  Decodes a raw SCGI response by splitting on the first `\\r\\n\\r\\n`
  sequence and returning the body portion.

  Returns `{:ok, body}` on success, or `{:error, :invalid_response}` when the
  blank-line separator is absent or the input is empty.

  Uses `:binary.split/2` (not `String.split/2`) so that arbitrary byte
  sequences in the XML body are handled correctly.
  """
  @spec decode_response(binary()) :: {:ok, binary()} | {:error, :invalid_response}
  def decode_response(raw) when is_binary(raw) and byte_size(raw) > 0 do
    case :binary.split(raw, "\r\n\r\n") do
      [_headers, body] -> {:ok, body}
      [_] -> {:error, :invalid_response}
    end
  end

  def decode_response(_), do: {:error, :invalid_response}
end
