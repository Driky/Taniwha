defmodule Taniwha.SCGI.UnixConnectionTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  alias Taniwha.SCGI.MockConnection
  alias Taniwha.SCGI.UnixConnection

  @unix_path "/var/run/rtorrent.sock"

  # ---------------------------------------------------------------------------
  # Behaviour contract tests via MockConnection
  # These document and verify the Connection behaviour interface.
  # ---------------------------------------------------------------------------

  describe "behaviour contract (MockConnection)" do
    test "successful connect → send → receive → close cycle" do
      socket = make_ref()

      MockConnection
      |> expect(:connect, fn {:unix, @unix_path} -> {:ok, socket} end)
      |> expect(:send_request, fn ^socket, "request" -> :ok end)
      |> expect(:receive_response, fn ^socket, 5000 -> {:ok, "response"} end)
      |> expect(:close, fn ^socket -> :ok end)

      assert {:ok, sock} = MockConnection.connect({:unix, @unix_path})
      assert :ok = MockConnection.send_request(sock, "request")
      assert {:ok, "response"} = MockConnection.receive_response(sock, 5000)
      assert :ok = MockConnection.close(sock)
    end

    test "connect failure: :enoent (socket file not found)" do
      MockConnection
      |> expect(:connect, fn {:unix, @unix_path} -> {:error, :enoent} end)

      assert {:error, :enoent} = MockConnection.connect({:unix, @unix_path})
    end

    test "connect failure: :eacces (permission denied)" do
      MockConnection
      |> expect(:connect, fn {:unix, @unix_path} -> {:error, :eacces} end)

      assert {:error, :eacces} = MockConnection.connect({:unix, @unix_path})
    end

    test "send failure after successful connect: :closed" do
      socket = make_ref()

      MockConnection
      |> expect(:connect, fn {:unix, @unix_path} -> {:ok, socket} end)
      |> expect(:send_request, fn ^socket, "data" -> {:error, :closed} end)

      assert {:ok, sock} = MockConnection.connect({:unix, @unix_path})
      assert {:error, :closed} = MockConnection.send_request(sock, "data")
    end

    test "receive timeout" do
      socket = make_ref()

      MockConnection
      |> expect(:connect, fn {:unix, @unix_path} -> {:ok, socket} end)
      |> expect(:receive_response, fn ^socket, 100 -> {:error, :timeout} end)

      assert {:ok, sock} = MockConnection.connect({:unix, @unix_path})
      assert {:error, :timeout} = MockConnection.receive_response(sock, 100)
    end
  end

  # ---------------------------------------------------------------------------
  # Real implementation tests
  # These are TDD-driven: red before implementation, green after.
  # ---------------------------------------------------------------------------

  describe "UnixConnection.connect/1" do
    test "returns {:error, :enoent} when socket file does not exist" do
      path = "/tmp/taniwha_nonexistent_#{System.unique_integer([:positive])}.sock"
      assert {:error, :enoent} = UnixConnection.connect({:unix, path})
    end
  end
end
