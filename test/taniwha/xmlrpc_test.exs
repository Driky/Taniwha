defmodule Taniwha.XMLRPCTest do
  use ExUnit.Case, async: true

  alias Taniwha.XMLRPC
  alias Taniwha.Test.Fixtures

  # ---------------------------------------------------------------------------
  # Batch 1 — encode_call/2 basic structure
  # ---------------------------------------------------------------------------

  describe "encode_call/2 basic structure" do
    test "returns a binary" do
      assert is_binary(XMLRPC.encode_call("d.name", []))
    end

    test "includes the method name" do
      xml = XMLRPC.encode_call("d.name", [])
      assert xml =~ "d.name"
    end

    test "has an empty <params> element when no params given" do
      xml = XMLRPC.encode_call("d.name", [])
      assert xml =~ "<params"
      assert xml =~ "</params>"
    end

    test "starts with XML declaration" do
      xml = XMLRPC.encode_call("d.name", [])
      assert String.starts_with?(xml, "<?xml")
    end

    test "root element is <methodCall>" do
      xml = XMLRPC.encode_call("d.name", [])
      assert xml =~ "<methodCall>"
      assert xml =~ "</methodCall>"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — encode_call/2 scalar type encoding
  # ---------------------------------------------------------------------------

  describe "encode_call/2 scalar type encoding" do
    test "encodes string param as <string>" do
      xml = XMLRPC.encode_call("m", ["hello"])
      assert xml =~ "<string>hello</string>"
    end

    test "encodes integer param as <i8>" do
      xml = XMLRPC.encode_call("m", [42])
      assert xml =~ "<i8>42</i8>"
    end

    test "encodes true as <boolean>1</boolean>" do
      xml = XMLRPC.encode_call("m", [true])
      assert xml =~ "<boolean>1</boolean>"
    end

    test "encodes false as <boolean>0</boolean>" do
      xml = XMLRPC.encode_call("m", [false])
      assert xml =~ "<boolean>0</boolean>"
    end

    test "encodes float param as <double>" do
      xml = XMLRPC.encode_call("m", [3.14])
      assert xml =~ "<double>"
      assert xml =~ "3.14"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — encode_call/2 complex types and escaping
  # ---------------------------------------------------------------------------

  describe "encode_call/2 complex types and escaping" do
    test "encodes list param as <array>" do
      xml = XMLRPC.encode_call("m", [["a", "b"]])
      assert xml =~ "<array>"
      assert xml =~ "<data>"
      assert xml =~ "<string>a</string>"
      assert xml =~ "<string>b</string>"
    end

    test "encodes map param as <struct>" do
      xml = XMLRPC.encode_call("m", [%{"key" => "val"}])
      assert xml =~ "<struct>"
      assert xml =~ "<member>"
      assert xml =~ "<name>key</name>"
      assert xml =~ "<string>val</string>"
    end

    test "escapes & in strings" do
      xml = XMLRPC.encode_call("m", ["a&b"])
      assert xml =~ "&amp;"
      refute xml =~ "a&b"
    end

    test "escapes < in strings" do
      xml = XMLRPC.encode_call("m", ["a<b"])
      assert xml =~ "&lt;"
      refute xml =~ "a<b"
    end

    test "encodes nested list (multicall shape)" do
      xml = XMLRPC.encode_call("m", [[["inner"]]])
      assert xml =~ "<array>"
      assert xml =~ "<string>inner</string>"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — encode_multicall/1
  # ---------------------------------------------------------------------------

  describe "encode_multicall/1" do
    test "method name is system.multicall" do
      xml = XMLRPC.encode_multicall([{"d.name", ["hash1"]}])
      assert xml =~ "system.multicall"
    end

    test "each call is encoded as a struct with methodName and params" do
      xml = XMLRPC.encode_multicall([{"d.name", ["abc"]}])
      assert xml =~ "<name>methodName</name>"
      assert xml =~ "<string>d.name</string>"
      assert xml =~ "<name>params</name>"
    end

    test "encodes multiple calls" do
      xml = XMLRPC.encode_multicall([{"d.name", ["h1"]}, {"d.size_bytes", ["h1"]}])
      assert xml =~ "d.name"
      assert xml =~ "d.size_bytes"
    end

    test "encodes empty list" do
      xml = XMLRPC.encode_multicall([])
      assert xml =~ "system.multicall"
      assert is_binary(xml)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 5 — decode_response/1 integer and string types
  # ---------------------------------------------------------------------------

  describe "decode_response/1 integer and string types" do
    test "decodes <string> value" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><string>hello world</string></value>
      </param></params></methodResponse>
      """

      assert {:ok, "hello world"} = XMLRPC.decode_response(xml)
    end

    test "decodes bare <value>text</value> (no type tag)" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value>bare text</value>
      </param></params></methodResponse>
      """

      assert {:ok, "bare text"} = XMLRPC.decode_response(xml)
    end

    test "decodes <i8> value" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><i8>1073741824</i8></value>
      </param></params></methodResponse>
      """

      assert {:ok, 1_073_741_824} = XMLRPC.decode_response(xml)
    end

    test "decodes <i4> value" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><i4>404</i4></value>
      </param></params></methodResponse>
      """

      assert {:ok, 404} = XMLRPC.decode_response(xml)
    end

    test "decodes <int> value" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><int>-1</int></value>
      </param></params></methodResponse>
      """

      assert {:ok, -1} = XMLRPC.decode_response(xml)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6 — decode_response/1 boolean, double, empty string
  # ---------------------------------------------------------------------------

  describe "decode_response/1 boolean, double, empty string" do
    test "decodes <boolean>1 as true" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><boolean>1</boolean></value>
      </param></params></methodResponse>
      """

      assert {:ok, true} = XMLRPC.decode_response(xml)
    end

    test "decodes <boolean>0 as false" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><boolean>0</boolean></value>
      </param></params></methodResponse>
      """

      assert {:ok, false} = XMLRPC.decode_response(xml)
    end

    test "decodes <double> value" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><double>3.14</double></value>
      </param></params></methodResponse>
      """

      assert {:ok, result} = XMLRPC.decode_response(xml)
      assert_in_delta result, 3.14, 0.001
    end

    test "decodes <string></string> as empty string" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><string></string></value>
      </param></params></methodResponse>
      """

      assert {:ok, ""} = XMLRPC.decode_response(xml)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 7 — decode_response/1 arrays and structs
  # ---------------------------------------------------------------------------

  describe "decode_response/1 arrays and structs" do
    test "decodes download_list.xml as list of 3 hashes" do
      xml = Fixtures.download_list_xml()
      assert {:ok, hashes} = XMLRPC.decode_response(xml)
      assert is_list(hashes)
      assert length(hashes) == 3
      assert "ABC123DEF456ABC123DEF456ABC123DEF456ABC1" in hashes
      assert "111222333444555666777888999AAABBBCCCDDD1" in hashes
      assert "FEEDFACEDEADBEEFFEEDFACEDEADBEEFFEEDFAC1" in hashes
    end

    test "decodes <struct> as map with string keys" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><struct>
          <member><name>foo</name><value><string>bar</string></value></member>
          <member><name>count</name><value><i8>7</i8></value></member>
        </struct></value>
      </param></params></methodResponse>
      """

      assert {:ok, %{"foo" => "bar", "count" => 7}} = XMLRPC.decode_response(xml)
    end

    test "decodes nested arrays" do
      xml = """
      <?xml version="1.0"?>
      <methodResponse><params><param>
        <value><array><data>
          <value><array><data>
            <value><string>inner</string></value>
          </data></array></value>
        </data></array></value>
      </param></params></methodResponse>
      """

      assert {:ok, [["inner"]]} = XMLRPC.decode_response(xml)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 8 — decode_response/1 faults
  # ---------------------------------------------------------------------------

  describe "decode_response/1 faults" do
    test "fault.xml returns {:error, ...} with fault_code and fault_string" do
      xml = Fixtures.fault_xml()
      assert {:error, fault} = XMLRPC.decode_response(xml)
      assert fault.fault_code == -501
      assert fault.fault_string == "Could not find info-hash."
    end

    test "fault has atom keys :fault_code and :fault_string" do
      xml = Fixtures.fault_xml()
      assert {:error, fault} = XMLRPC.decode_response(xml)
      assert Map.has_key?(fault, :fault_code)
      assert Map.has_key?(fault, :fault_string)
    end

    test "fault code decoded from <i4> is an integer" do
      xml = Fixtures.fault_xml()
      assert {:error, %{fault_code: code}} = XMLRPC.decode_response(xml)
      assert is_integer(code)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 9 — decode_response/1 multicall, error handling
  # ---------------------------------------------------------------------------

  describe "decode_response/1 multicall and error handling" do
    test "multicall.xml returns list of 7 single-element arrays" do
      xml = Fixtures.multicall_xml()
      assert {:ok, results} = XMLRPC.decode_response(xml)
      assert is_list(results)
      assert length(results) == 7
      assert Enum.all?(results, &(is_list(&1) and length(&1) == 1))
    end

    test "multicall.xml first result is the torrent name string" do
      xml = Fixtures.multicall_xml()
      assert {:ok, [[name] | _]} = XMLRPC.decode_response(xml)
      assert name == "Ubuntu 24.04.2 LTS"
    end

    test "multicall.xml includes boolean true result" do
      xml = Fixtures.multicall_xml()
      assert {:ok, results} = XMLRPC.decode_response(xml)
      values = Enum.map(results, fn [v] -> v end)
      assert true in values
    end

    test "multicall.xml bare text result is decoded as string" do
      xml = Fixtures.multicall_xml()
      assert {:ok, results} = XMLRPC.decode_response(xml)
      values = Enum.map(results, fn [v] -> v end)
      assert "/downloads/ubuntu" in values
    end

    test "malformed XML returns {:error, {:parse_error, _}}" do
      assert {:error, {:parse_error, _}} = XMLRPC.decode_response("<<not xml>>")
    end

    test "empty binary returns {:error, {:parse_error, _}}" do
      assert {:error, {:parse_error, _}} = XMLRPC.decode_response("")
    end
  end
end
