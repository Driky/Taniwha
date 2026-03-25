defmodule Taniwha.XMLRPC do
  @moduledoc """
  XML-RPC codec for rtorrent communication.

  Provides pure-functional encode/decode between Elixir terms and the XML-RPC
  wire format used by rtorrent over SCGI.

  ## Type mapping

  ### Encoding (Elixir → XML-RPC)
  - `{:base64, binary()}` → `<base64>` (Base64-encoded, for raw binary payloads)
  - `binary()` → `<string>` (with HTML entity escaping)
  - `integer()` → `<i8>`
  - `float()` → `<double>`
  - `true` / `false` → `<boolean>1</boolean>` / `<boolean>0</boolean>`
  - `list()` → `<array><data>…</data></array>`
  - `map()` → `<struct><member>…</member></struct>`

  ### Decoding (XML-RPC → Elixir)
  - `<string>` or bare `<value>text</value>` → `String.t()`
  - `<i8>`, `<i4>`, `<int>` → `integer()`
  - `<boolean>` → `true | false`
  - `<double>` → `float()`
  - `<array>` → `list()`
  - `<struct>` → `%{String.t() => term()}` (string keys)
  - `<fault>` → `{:error, %{fault_code: integer(), fault_string: String.t()}}`
  """

  import SweetXml

  @type xmlrpc_value ::
          {:base64, binary()}
          | String.t()
          | integer()
          | float()
          | boolean()
          | list()
          | %{optional(String.t()) => xmlrpc_value()}

  @type call :: {String.t(), list()}

  @doc """
  Encodes a single XML-RPC method call.

  Returns the full XML document as a binary, including the XML declaration.

  ## Examples

      iex> xml = Taniwha.XMLRPC.encode_call("d.name", ["abc123"])
      iex> xml =~ "<methodName>d.name</methodName>"
      true
  """
  @spec encode_call(String.t(), list()) :: binary()
  def encode_call(method, params) when is_binary(method) and is_list(params) do
    params_xml =
      Enum.map_join(params, "", fn p -> "<param><value>#{encode_value(p)}</value></param>" end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <methodCall>
    <methodName>#{method}</methodName>
    <params>#{params_xml}</params>
    </methodCall>
    """
  end

  @doc """
  Encodes a `system.multicall` request from a list of `{method, params}` tuples.

  Each tuple is converted to a struct with `methodName` and `params` keys, then
  the entire list is passed as the single argument to `system.multicall`.

  ## Examples

      iex> xml = Taniwha.XMLRPC.encode_multicall([{"d.name", ["hash"]}, {"d.size_bytes", ["hash"]}])
      iex> xml =~ "system.multicall"
      true
  """
  @spec encode_multicall(list(call())) :: binary()
  def encode_multicall(calls) when is_list(calls) do
    struct_list =
      Enum.map(calls, fn {method, params} ->
        %{"methodName" => method, "params" => params}
      end)

    encode_call("system.multicall", [struct_list])
  end

  @doc """
  Decodes an XML-RPC `<methodResponse>` binary.

  Returns `{:ok, value}` on success, `{:error, reason}` on fault or parse
  failure.

  - Fault responses return `{:error, %{fault_code: integer(), fault_string: String.t()}}`.
  - Parse errors return `{:error, {:parse_error, reason}}`.
  """
  @spec decode_response(binary()) :: {:ok, xmlrpc_value()} | {:error, term()}
  def decode_response(xml) when is_binary(xml) do
    try do
      parsed = SweetXml.parse(xml)
      decode_parsed(parsed)
    rescue
      e -> {:error, {:parse_error, e}}
    catch
      :exit, reason -> {:error, {:parse_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — decoding
  # ---------------------------------------------------------------------------

  @spec decode_parsed(any()) :: {:ok, xmlrpc_value()} | {:error, term()}
  defp decode_parsed(doc) do
    case xpath(doc, ~x"//methodResponse/fault"o) do
      nil -> decode_params(doc)
      fault_node -> decode_fault(fault_node)
    end
  end

  @spec decode_params(any()) :: {:ok, xmlrpc_value()} | {:error, term()}
  defp decode_params(doc) do
    value_node = xpath(doc, ~x"//methodResponse/params/param/value"e)
    {:ok, decode_value_node(value_node)}
  end

  @spec decode_fault(any()) :: {:error, %{fault_code: integer(), fault_string: String.t()}}
  defp decode_fault(fault_node) do
    struct_node = xpath(fault_node, ~x"value/struct"e)
    member_nodes = xpath(struct_node, ~x"member"el)

    fault_map =
      Map.new(member_nodes, fn member ->
        name = xpath(member, ~x"name/text()"s)
        value_node = xpath(member, ~x"value"e)
        {name, decode_value_node(value_node)}
      end)

    {:error,
     %{
       fault_code: Map.get(fault_map, "faultCode", 0),
       fault_string: Map.get(fault_map, "faultString", "")
     }}
  end

  @spec decode_value_node(any()) :: xmlrpc_value()
  defp decode_value_node(node) do
    cond do
      child = xpath(node, ~x"string"o) ->
        xpath(child, ~x"text()"s)

      child = xpath(node, ~x"i8"o) ->
        xpath(child, ~x"text()"i)

      child = xpath(node, ~x"i4"o) ->
        xpath(child, ~x"text()"i)

      child = xpath(node, ~x"int"o) ->
        xpath(child, ~x"text()"i)

      child = xpath(node, ~x"boolean"o) ->
        xpath(child, ~x"text()"i) == 1

      child = xpath(node, ~x"double"o) ->
        parse_float(xpath(child, ~x"text()"s))

      child = xpath(node, ~x"array"o) ->
        decode_array(child)

      child = xpath(node, ~x"struct"o) ->
        decode_struct(child)

      true ->
        # bare <value>text</value> — no type tag
        xpath(node, ~x"text()"s)
    end
  end

  @spec decode_array(any()) :: list()
  defp decode_array(array_node) do
    value_nodes = xpath(array_node, ~x"data/value"el)
    Enum.map(value_nodes, &decode_value_node/1)
  end

  @spec decode_struct(any()) :: %{optional(String.t()) => xmlrpc_value()}
  defp decode_struct(struct_node) do
    member_nodes = xpath(struct_node, ~x"member"el)

    Map.new(member_nodes, fn member ->
      name = xpath(member, ~x"name/text()"s)
      value_node = xpath(member, ~x"value"e)
      {name, decode_value_node(value_node)}
    end)
  end

  @spec parse_float(String.t()) :: float()
  defp parse_float(s) do
    case Float.parse(s) do
      {f, _rest} -> f
      :error -> 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # Private — encoding
  # ---------------------------------------------------------------------------

  @spec encode_value(xmlrpc_value()) :: String.t()
  defp encode_value({:base64, data}) when is_binary(data) do
    "<base64>#{Base.encode64(data)}</base64>"
  end

  defp encode_value(v) when is_binary(v) do
    "<string>#{escape_xml(v)}</string>"
  end

  defp encode_value(v) when is_integer(v) do
    "<i8>#{v}</i8>"
  end

  defp encode_value(v) when is_float(v) do
    "<double>#{v}</double>"
  end

  defp encode_value(true) do
    "<boolean>1</boolean>"
  end

  defp encode_value(false) do
    "<boolean>0</boolean>"
  end

  defp encode_value(v) when is_list(v) do
    items = Enum.map_join(v, "", fn item -> "<value>#{encode_value(item)}</value>" end)
    "<array><data>#{items}</data></array>"
  end

  defp encode_value(v) when is_map(v) do
    members =
      Enum.map_join(v, "", fn {k, val} ->
        "<member><name>#{escape_xml(k)}</name><value>#{encode_value(val)}</value></member>"
      end)

    "<struct>#{members}</struct>"
  end

  @spec escape_xml(String.t()) :: String.t()
  defp escape_xml(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
