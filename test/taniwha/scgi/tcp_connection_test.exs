defmodule Taniwha.SCGI.TcpConnectionTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  alias Taniwha.SCGI.MockConnection
  alias Taniwha.SCGI.TcpConnection

  # ---------------------------------------------------------------------------
  # Behaviour contract tests via MockConnection
  # These document and verify the Connection behaviour interface.
  # ---------------------------------------------------------------------------

  describe "behaviour contract (MockConnection)" do
    test "successful connect → send → receive → close cycle" do
      socket = make_ref()

      MockConnection
      |> expect(:connect, fn {:tcp, "localhost", 5000} -> {:ok, socket} end)
      |> expect(:send_request, fn ^socket, "request" -> :ok end)
      |> expect(:receive_response, fn ^socket, 5000 -> {:ok, "response"} end)
      |> expect(:close, fn ^socket -> :ok end)

      assert {:ok, sock} = MockConnection.connect({:tcp, "localhost", 5000})
      assert :ok = MockConnection.send_request(sock, "request")
      assert {:ok, "response"} = MockConnection.receive_response(sock, 5000)
      assert :ok = MockConnection.close(sock)
    end

    test "connect failure: :econnrefused" do
      MockConnection
      |> expect(:connect, fn {:tcp, "localhost", 5000} -> {:error, :econnrefused} end)

      assert {:error, :econnrefused} = MockConnection.connect({:tcp, "localhost", 5000})
    end

    test "connect failure: :timeout" do
      MockConnection
      |> expect(:connect, fn {:tcp, "localhost", 5000} -> {:error, :timeout} end)

      assert {:error, :timeout} = MockConnection.connect({:tcp, "localhost", 5000})
    end

    test "connect failure: :nxdomain (host not found)" do
      MockConnection
      |> expect(:connect, fn {:tcp, "no.such.host.invalid", 5000} -> {:error, :nxdomain} end)

      assert {:error, :nxdomain} = MockConnection.connect({:tcp, "no.such.host.invalid", 5000})
    end

    test "send failure after connect: :closed" do
      socket = make_ref()

      MockConnection
      |> expect(:connect, fn {:tcp, "localhost", 5000} -> {:ok, socket} end)
      |> expect(:send_request, fn ^socket, "data" -> {:error, :closed} end)

      assert {:ok, sock} = MockConnection.connect({:tcp, "localhost", 5000})
      assert {:error, :closed} = MockConnection.send_request(sock, "data")
    end

    test "receive timeout" do
      socket = make_ref()

      MockConnection
      |> expect(:connect, fn {:tcp, "localhost", 5000} -> {:ok, socket} end)
      |> expect(:receive_response, fn ^socket, 100 -> {:error, :timeout} end)

      assert {:ok, sock} = MockConnection.connect({:tcp, "localhost", 5000})
      assert {:error, :timeout} = MockConnection.receive_response(sock, 100)
    end
  end

  # ---------------------------------------------------------------------------
  # Real implementation tests
  # These are TDD-driven: red before implementation, green after.
  # ---------------------------------------------------------------------------

  describe "TcpConnection.connect/1" do
    test "returns {:error, :econnrefused} when no server is listening" do
      # Port 1 is privileged and never listening — guaranteed :econnrefused
      assert {:error, :econnrefused} = TcpConnection.connect({:tcp, "localhost", 1})
    end

    test "returns an error tuple for a non-existent hostname" do
      assert {:error, _reason} = TcpConnection.connect({:tcp, "no.such.host.invalid", 5000})
    end
  end
end
