defmodule Taniwha.RPC.ClientTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mox

  alias Taniwha.RPC.Client
  alias Taniwha.SCGI.MockConnection
  alias Taniwha.Test.Fixtures

  setup :verify_on_exit!

  setup do
    # Allow the supervisor-started GenServer to use the mock
    Mox.allow(MockConnection, self(), Process.whereis(Client))
    :ok
  end

  defp scgi_response(xml),
    do: "HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n" <> xml

  # ---------------------------------------------------------------------------
  # Batch 1 — call/2 happy path
  # ---------------------------------------------------------------------------

  describe "call/2 happy path" do
    test "successful call returns decoded value" do
      xml = Fixtures.torrent_name_xml()
      response = scgi_response(xml)

      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:ok, response} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:ok, "Ubuntu 24.04.2 LTS"} = Client.call("d.name", ["abc123"])
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — call/2 error cases
  # ---------------------------------------------------------------------------

  describe "call/2 error cases" do
    test "connect failure returns :connection_failed without calling close" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:error, :enoent} end)

      assert {:error, :connection_failed} = Client.call("d.name", ["abc123"])
    end

    test "send failure closes socket and returns error" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> {:error, :closed} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:error, :closed} = Client.call("d.name", ["abc123"])
    end

    test "receive timeout closes socket and returns error" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:error, :timeout} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:error, :timeout} = Client.call("d.name", ["abc123"])
    end

    test "GenServer stays alive after error" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:error, :enoent} end)

      Client.call("d.name", ["abc123"])

      assert Process.alive?(Process.whereis(Client))
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — multicall/1 happy path
  # ---------------------------------------------------------------------------

  describe "multicall/1 happy path" do
    test "returns list of per-call result arrays" do
      xml = Fixtures.multicall_xml()
      response = scgi_response(xml)

      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:ok, response} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      calls = [
        {"d.name", ["hash"]},
        {"d.size_bytes", ["hash"]},
        {"d.completed_bytes", ["hash"]},
        {"d.complete", ["hash"]},
        {"d.hashing", ["hash"]},
        {"d.timestamp.started", ["hash"]},
        {"d.directory", ["hash"]}
      ]

      assert {:ok, results} = Client.multicall(calls)
      assert length(results) == 7
      assert [["Ubuntu 24.04.2 LTS"] | _] = results
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3b — call/2 retry on connect failure
  # ---------------------------------------------------------------------------

  describe "call/2 retry on connect failure" do
    setup do
      Application.put_env(:taniwha, :rpc_max_retries, 3)
      on_exit(fn -> Application.put_env(:taniwha, :rpc_max_retries, 0) end)
    end

    test "succeeds on 2nd attempt after first connect fails" do
      xml = Fixtures.torrent_name_xml()
      response = scgi_response(xml)

      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:error, :econnrefused} end)
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:ok, response} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:ok, "Ubuntu 24.04.2 LTS"} = Client.call("d.name", ["abc123"])
    end

    test "returns {:error, :connection_failed} after max retries (3) exhausted" do
      # 1 initial attempt + 3 retries = 4 total connect calls
      MockConnection
      |> expect(:connect, 4, fn {:unix, _} -> {:error, :econnrefused} end)

      assert {:error, :connection_failed} = Client.call("d.name", ["abc123"])
    end

    test "does NOT retry on send error — only connect failures trigger retry" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> {:error, :closed} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      # Only 1 connect expected
      assert {:error, :closed} = Client.call("d.name", ["abc123"])
    end

    test "does NOT retry on receive error" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:error, :timeout} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      # Only 1 connect expected
      assert {:error, :timeout} = Client.call("d.name", ["abc123"])
    end

    test "GenServer stays alive after all retries exhausted" do
      MockConnection
      |> expect(:connect, 4, fn {:unix, _} -> {:error, :econnrefused} end)

      assert {:error, :connection_failed} = Client.call("d.name", ["abc123"])
      assert Process.alive?(Process.whereis(Client))
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — decode failures
  # ---------------------------------------------------------------------------

  describe "decode failures" do
    test "invalid SCGI framing returns error" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout ->
        {:ok, "HTTP/1.1 200 OK\nno-blank-line-here"}
      end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:error, :invalid_response} = Client.call("d.name", ["abc123"])
    end

    test "malformed XML body returns error" do
      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout ->
        {:ok, scgi_response("this is not xml at all <<<<")}
      end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:error, _reason} = Client.call("d.name", ["abc123"])
    end

    test "XML-RPC fault response returns structured error" do
      xml = Fixtures.fault_xml()
      response = scgi_response(xml)

      MockConnection
      |> expect(:connect, fn {:unix, _} -> {:ok, :fake_socket} end)
      |> expect(:send_request, fn :fake_socket, _frame -> :ok end)
      |> expect(:receive_response, fn :fake_socket, _timeout -> {:ok, response} end)
      |> expect(:close, fn :fake_socket -> :ok end)

      assert {:error, %{fault_code: -501, fault_string: "Could not find info-hash."}} =
               Client.call("d.name", ["bad-hash"])
    end
  end
end
