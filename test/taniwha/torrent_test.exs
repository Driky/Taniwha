defmodule Taniwha.TorrentTest do
  use ExUnit.Case, async: true

  alias Taniwha.Torrent

  # ---------------------------------------------------------------------------
  # Batch 3 — struct + progress/1 + ratio_display/1
  # ---------------------------------------------------------------------------

  describe "struct" do
    # @enforce_keys is a compile-time check; exercise it via __struct__/1 at runtime.
    test "raises when :hash is missing" do
      assert_raise ArgumentError, fn ->
        Torrent.__struct__(name: "Test Torrent")
      end
    end

    test "raises when :name is missing" do
      assert_raise ArgumentError, fn ->
        Torrent.__struct__(hash: "abc123")
      end
    end

    test "creates a Torrent with required fields" do
      torrent = %Torrent{hash: "abc123", name: "Test Torrent"}
      assert torrent.hash == "abc123"
      assert torrent.name == "Test Torrent"
    end
  end

  describe "progress/1" do
    test "returns 0.0 when size is 0" do
      torrent = %Torrent{hash: "a", name: "b", size: 0, completed_bytes: 0}
      assert Torrent.progress(torrent) == 0.0
    end

    test "returns 0.5 for 50% completed" do
      torrent = %Torrent{hash: "a", name: "b", size: 1000, completed_bytes: 500}
      assert Torrent.progress(torrent) == 0.5
    end

    test "returns a float" do
      torrent = %Torrent{hash: "a", name: "b", size: 3, completed_bytes: 1}
      assert is_float(Torrent.progress(torrent))
    end
  end

  describe "ratio_display/1" do
    test "0 ratio returns 0.0" do
      assert Torrent.ratio_display(0) == 0.0
    end

    test "1000 ratio returns 1.0" do
      assert Torrent.ratio_display(1000) == 1.0
    end

    test "1500 ratio returns 1.5" do
      assert Torrent.ratio_display(1500) == 1.5
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4 — status/1
  # ---------------------------------------------------------------------------

  describe "status/1" do
    test "returns :checking when is_hash_checking is true" do
      torrent = %Torrent{hash: "a", name: "b", is_hash_checking: true}
      assert Torrent.status(torrent) == :checking
    end

    test "returns :downloading when started, active, and incomplete" do
      torrent = %Torrent{hash: "a", name: "b", state: :started, is_active: true, complete: false}
      assert Torrent.status(torrent) == :downloading
    end

    test "returns :seeding when started, active, and complete" do
      torrent = %Torrent{hash: "a", name: "b", state: :started, is_active: true, complete: true}
      assert Torrent.status(torrent) == :seeding
    end

    test "returns :paused when started but not active" do
      torrent = %Torrent{hash: "a", name: "b", state: :started, is_active: false}
      assert Torrent.status(torrent) == :paused
    end

    test "returns :stopped when state is :stopped" do
      torrent = %Torrent{hash: "a", name: "b", state: :stopped}
      assert Torrent.status(torrent) == :stopped
    end

    test "returns :unknown for unrecognised state" do
      torrent = %{%Torrent{hash: "a", name: "b"} | state: :other}
      assert Torrent.status(torrent) == :unknown
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4b — eta/1
  # ---------------------------------------------------------------------------

  describe "eta/1" do
    test "returns 0 when torrent is complete" do
      torrent = %Torrent{hash: "a", name: "b", complete: true}
      assert Torrent.eta(torrent) == 0
    end

    test "returns calculated seconds when download_rate > 0" do
      torrent = %Torrent{
        hash: "a",
        name: "b",
        size: 1_000,
        completed_bytes: 500,
        download_rate: 100
      }

      assert Torrent.eta(torrent) == 5
    end

    test "returns nil when download_rate is 0" do
      torrent = %Torrent{hash: "a", name: "b", size: 1_000, completed_bytes: 0, download_rate: 0}
      assert Torrent.eta(torrent) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 5 — from_rpc_values/2 + rpc_fields/0
  # ---------------------------------------------------------------------------

  describe "from_rpc_values/2" do
    @hash "AABBCCDDEEFF00112233445566778899AABBCCDD"

    # Field order: name, size_bytes, completed_bytes, up.rate, down.rate,
    #              ratio, state, is_active, complete, is_hash_checking,
    #              peers_connected, timestamp.started, timestamp.finished, base_path,
    #              custom1 (label)
    @values [
      "Ubuntu 22.04",
      1_000_000,
      500_000,
      1024,
      2048,
      1500,
      1,
      1,
      0,
      0,
      5,
      1_700_000_000,
      0,
      "/downloads/ubuntu",
      ""
    ]

    setup do
      {:ok, torrent: Torrent.from_rpc_values(@hash, @values)}
    end

    test "sets hash", %{torrent: t} do
      assert t.hash == @hash
    end

    test "sets name", %{torrent: t} do
      assert t.name == "Ubuntu 22.04"
    end

    test "converts ratio integer to float", %{torrent: t} do
      assert t.ratio == 1.5
    end

    test "decodes state 1 as :started", %{torrent: t} do
      assert t.state == :started
    end

    test "decodes is_active as boolean", %{torrent: t} do
      assert t.is_active == true
    end

    test "decodes complete as boolean", %{torrent: t} do
      assert t.complete == false
    end

    test "decodes is_hash_checking as boolean", %{torrent: t} do
      assert t.is_hash_checking == false
    end

    test "maps timestamp 0 to nil", %{torrent: t} do
      assert t.finished_at == nil
    end

    test "maps non-zero timestamp to DateTime", %{torrent: t} do
      assert %DateTime{} = t.started_at
      assert t.started_at == DateTime.from_unix!(1_700_000_000, :second)
    end

    test "maps empty base_path to nil" do
      values = List.replace_at(@values, 13, "")
      torrent = Torrent.from_rpc_values(@hash, values)
      assert torrent.base_path == nil
    end

    test "sets files to nil (files not populated in from_rpc_values)", %{torrent: t} do
      assert t.files == nil
    end
  end

  describe "rpc_fields/0" do
    test "returns a list of 15 strings" do
      fields = Torrent.rpc_fields()
      assert is_list(fields)
      assert length(fields) == 15
      assert Enum.all?(fields, &is_binary/1)
    end
  end
end
