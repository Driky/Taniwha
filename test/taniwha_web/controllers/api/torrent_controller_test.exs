defmodule TaniwhaWeb.API.TorrentControllerTest do
  use TaniwhaWeb.ConnCase, async: false

  import Mox

  alias Taniwha.{MockCommands, State.Store, Torrent}

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Store.clear()
    on_exit(fn -> Store.clear() end)
    :ok
  end

  defp with_auth(conn) do
    {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp torrent_fixture(hash \\ "abc123def456abc123def456abc123de") do
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

  # ---------------------------------------------------------------------------
  # GET /api/v1/torrents
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/torrents" do
    test "returns 200 with list of torrents", %{conn: conn} do
      Store.put_torrent(torrent_fixture())
      conn = conn |> with_auth() |> get("/api/v1/torrents")

      assert %{"torrents" => [torrent_map]} = json_response(conn, 200)
      assert torrent_map["hash"] == "abc123def456abc123def456abc123de"
      assert torrent_map["name"] == "Test Torrent"
      assert torrent_map["size"] == 1_000_000
      assert torrent_map["state"] == "started"
    end

    test "returns 200 with empty list when store is empty", %{conn: conn} do
      conn = conn |> with_auth() |> get("/api/v1/torrents")

      assert %{"torrents" => []} = json_response(conn, 200)
    end

    test "returns 401 without auth header", %{conn: conn} do
      conn = get(conn, "/api/v1/torrents")

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/torrents/:hash
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/torrents/:hash" do
    test "returns 200 with torrent when found", %{conn: conn} do
      hash = "abc123def456abc123def456abc123de"
      Store.put_torrent(torrent_fixture(hash))
      conn = conn |> with_auth() |> get("/api/v1/torrents/#{hash}")

      assert %{"torrent" => torrent_map} = json_response(conn, 200)
      assert torrent_map["hash"] == hash
      assert torrent_map["name"] == "Test Torrent"
    end

    test "returns 404 when torrent not found", %{conn: conn} do
      conn = conn |> with_auth() |> get("/api/v1/torrents/unknownhash0000000000000000000001")

      assert %{"error" => "not_found"} = json_response(conn, 404)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/torrents — magnet URL
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/torrents with magnet_url" do
    test "returns 201 queued when load_url succeeds", %{conn: conn} do
      expect(MockCommands, :load_url, fn _url -> :ok end)

      conn =
        conn
        |> with_auth()
        |> post("/api/v1/torrents", %{"magnet_url" => "magnet:?xt=urn:btih:abc123"})

      assert %{"status" => "queued"} = json_response(conn, 201)
    end

    test "returns 422 when load_url fails", %{conn: conn} do
      expect(MockCommands, :load_url, fn _url -> {:error, :connection_refused} end)

      conn =
        conn
        |> with_auth()
        |> post("/api/v1/torrents", %{"magnet_url" => "magnet:?xt=urn:btih:abc123"})

      assert json_response(conn, 422)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/torrents — file upload
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/torrents with torrent file upload" do
    test "returns 201 queued when load_raw succeeds", %{conn: conn} do
      path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer([:positive])}.torrent")
      File.write!(path, "fake torrent data")
      on_exit(fn -> File.rm(path) end)

      expect(MockCommands, :load_raw, fn _binary -> :ok end)

      upload = %Plug.Upload{
        path: path,
        filename: "test.torrent",
        content_type: "application/x-bittorrent"
      }

      conn = conn |> with_auth() |> post("/api/v1/torrents", %{"torrent" => upload})

      assert %{"status" => "queued"} = json_response(conn, 201)
    end

    test "returns 422 when load_raw fails", %{conn: conn} do
      path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer([:positive])}.torrent")
      File.write!(path, "bad data")
      on_exit(fn -> File.rm(path) end)

      expect(MockCommands, :load_raw, fn _binary -> {:error, :invalid_torrent} end)

      upload = %Plug.Upload{
        path: path,
        filename: "bad.torrent",
        content_type: "application/x-bittorrent"
      }

      conn = conn |> with_auth() |> post("/api/v1/torrents", %{"torrent" => upload})

      assert json_response(conn, 422)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/torrents — invalid body
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/torrents with invalid body" do
    test "returns 422 when neither magnet_url nor torrent file is provided", %{conn: conn} do
      conn = conn |> with_auth() |> post("/api/v1/torrents", %{})

      assert %{"error" => "magnet_url or torrent file required"} = json_response(conn, 422)
    end
  end
end
