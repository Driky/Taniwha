defmodule TaniwhaWeb.API.ThrottleControllerTest do
  @moduledoc false

  use TaniwhaWeb.ConnCase, async: false

  import Mox

  alias Taniwha.{MockCommands, ThrottleStore}

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    ThrottleStore.reset()
    on_exit(fn -> ThrottleStore.reset() end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Batch 1: GET /api/v1/throttle
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/throttle" do
    test "returns 200 with limits and presets", %{conn: conn} do
      conn = conn |> with_auth() |> get("/api/v1/throttle")

      assert %{
               "download_limit" => 0,
               "upload_limit" => 0,
               "presets" => presets
             } = json_response(conn, 200)

      assert is_list(presets)
      assert length(presets) > 0
      [first | _] = presets
      assert Map.has_key?(first, "value")
      assert Map.has_key?(first, "unit")
      assert Map.has_key?(first, "label")
      assert is_integer(first["value"])
      assert is_binary(first["unit"])
      assert is_binary(first["label"])
    end

    test "returns 401 without auth", %{conn: conn} do
      conn = get(conn, "/api/v1/throttle")
      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2: PUT /api/v1/throttle/download
  # ---------------------------------------------------------------------------

  describe "PUT /api/v1/throttle/download" do
    test "returns 204 with valid limit", %{conn: conn} do
      expect(MockCommands, :set_download_limit, fn 5_242_880 -> :ok end)

      conn = conn |> with_auth() |> put("/api/v1/throttle/download", %{"limit" => 5_242_880})

      assert response(conn, 204) == ""
    end

    test "returns 204 with limit 0 (unlimited)", %{conn: conn} do
      expect(MockCommands, :set_download_limit, fn 0 -> :ok end)

      conn = conn |> with_auth() |> put("/api/v1/throttle/download", %{"limit" => 0})

      assert response(conn, 204) == ""
    end

    test "returns 422 with limit -1", %{conn: conn} do
      conn = conn |> with_auth() |> put("/api/v1/throttle/download", %{"limit" => -1})

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 422 with non-integer limit", %{conn: conn} do
      conn = conn |> with_auth() |> put("/api/v1/throttle/download", %{"limit" => "fast"})

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 503 when rtorrent unreachable", %{conn: conn} do
      expect(MockCommands, :set_download_limit, fn _ -> {:error, :econnrefused} end)

      conn = conn |> with_auth() |> put("/api/v1/throttle/download", %{"limit" => 1_048_576})

      assert %{"error" => _} = json_response(conn, 503)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3: PUT /api/v1/throttle/upload
  # ---------------------------------------------------------------------------

  describe "PUT /api/v1/throttle/upload" do
    test "returns 204 with valid limit", %{conn: conn} do
      expect(MockCommands, :set_upload_limit, fn 1_048_576 -> :ok end)

      conn = conn |> with_auth() |> put("/api/v1/throttle/upload", %{"limit" => 1_048_576})

      assert response(conn, 204) == ""
    end

    test "returns 422 with limit -1", %{conn: conn} do
      conn = conn |> with_auth() |> put("/api/v1/throttle/upload", %{"limit" => -1})

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 422 with non-integer limit", %{conn: conn} do
      conn = conn |> with_auth() |> put("/api/v1/throttle/upload", %{"limit" => "fast"})

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 503 when rtorrent unreachable", %{conn: conn} do
      expect(MockCommands, :set_upload_limit, fn _ -> {:error, :econnrefused} end)

      conn = conn |> with_auth() |> put("/api/v1/throttle/upload", %{"limit" => 1_048_576})

      assert %{"error" => _} = json_response(conn, 503)
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4: PUT /api/v1/throttle/presets
  # ---------------------------------------------------------------------------

  describe "PUT /api/v1/throttle/presets" do
    test "returns 200 with valid unsorted list, response sorted by bytes asc", %{conn: conn} do
      # Unsorted: 5 MiB/s before 512 KiB/s — response should be sorted ascending by bytes
      presets = [
        %{"value" => 5, "unit" => "mib_s"},
        %{"value" => 512, "unit" => "kib_s"}
      ]

      conn = conn |> with_auth() |> put("/api/v1/throttle/presets", %{"presets" => presets})

      assert %{"presets" => resp_presets} = json_response(conn, 200)
      assert length(resp_presets) == 2

      [first, second] = resp_presets
      # 512 KiB/s = 524_288 bytes < 5 MiB/s = 5_242_880 bytes
      assert first["value"] == 512
      assert first["unit"] == "kib_s"
      assert first["label"] == "512 KiB/s"
      assert second["value"] == 5
      assert second["unit"] == "mib_s"
      assert second["label"] == "5 MiB/s"
    end

    test "returns 422 with invalid unit", %{conn: conn} do
      presets = [%{"value" => 5, "unit" => "gb_s"}]

      conn = conn |> with_auth() |> put("/api/v1/throttle/presets", %{"presets" => presets})

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 422 with empty list", %{conn: conn} do
      conn = conn |> with_auth() |> put("/api/v1/throttle/presets", %{"presets" => []})

      assert %{"error" => _} = json_response(conn, 422)
    end

    test "returns 422 with duplicates after byte normalisation", %{conn: conn} do
      # 1 MiB/s == 1024 KiB/s → duplicate after byte normalisation
      presets = [
        %{"value" => 1, "unit" => "mib_s"},
        %{"value" => 1024, "unit" => "kib_s"}
      ]

      conn = conn |> with_auth() |> put("/api/v1/throttle/presets", %{"presets" => presets})

      assert %{"error" => _} = json_response(conn, 422)
    end
  end
end
