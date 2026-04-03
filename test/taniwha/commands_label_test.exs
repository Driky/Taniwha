defmodule Taniwha.CommandsLabelTest do
  use ExUnit.Case, async: true

  import Mox

  alias Taniwha.Commands
  alias Taniwha.State.Store
  alias Taniwha.Torrent

  setup :verify_on_exit!

  # Raw RPC values in Torrent.rpc_fields/0 order, including label and tracker_url.
  defp torrent_rpc_values(overrides \\ %{}) do
    defaults = %{
      name: "My Torrent",
      size: 1_000_000,
      completed_bytes: 500_000,
      up_rate: 100,
      down_rate: 200,
      ratio: 1500,
      state: 1,
      is_active: 1,
      complete: 0,
      is_hash_checking: 0,
      peers_connected: 3,
      ts_started: 1_609_459_200,
      ts_finished: 0,
      base_path: "/downloads",
      label: "",
      tracker_url: ""
    }

    m = Map.merge(defaults, overrides)

    [
      m.name,
      m.size,
      m.completed_bytes,
      m.up_rate,
      m.down_rate,
      m.ratio,
      m.state,
      m.is_active,
      m.complete,
      m.is_hash_checking,
      m.peers_connected,
      m.ts_started,
      m.ts_finished,
      m.base_path,
      m.label,
      m.tracker_url
    ]
  end

  # ---------------------------------------------------------------------------
  # Batch 1 — Torrent struct: label field
  # ---------------------------------------------------------------------------

  describe "Torrent.from_rpc_values/2 label" do
    test "parses label from 15th RPC value" do
      torrent = Torrent.from_rpc_values("abc123", torrent_rpc_values(%{label: "Linux"}))
      assert torrent.label == "Linux"
    end

    test "normalises empty string to nil" do
      torrent = Torrent.from_rpc_values("abc123", torrent_rpc_values(%{label: ""}))
      assert torrent.label == nil
    end

    test "preserves non-empty label as-is" do
      torrent = Torrent.from_rpc_values("abc123", torrent_rpc_values(%{label: "my label"}))
      assert torrent.label == "my label"
    end

    test "label is in diff_fields/0" do
      assert :label in Torrent.diff_fields()
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2 — set_label/2, remove_label/1, get_all_labels/0
  # ---------------------------------------------------------------------------

  describe "set_label/2" do
    test "calls d.custom1.set with hash and label" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.custom1.set", ["abc123", "Linux"] ->
        {:ok, 0}
      end)

      assert Commands.set_label("abc123", "Linux") == :ok
    end

    test "propagates RPC error" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.custom1.set", [_, _] ->
        {:error, :timeout}
      end)

      assert Commands.set_label("abc123", "Linux") == {:error, :timeout}
    end
  end

  describe "remove_label/1" do
    test "calls d.custom1.set with empty string" do
      expect(Taniwha.RPC.MockClient, :call, fn "d.custom1.set", ["abc123", ""] ->
        {:ok, 0}
      end)

      assert Commands.remove_label("abc123") == :ok
    end
  end

  describe "get_all_labels/0" do
    setup do
      Store.clear()
      on_exit(&Store.clear/0)
    end

    test "returns sorted unique labels from store" do
      Store.put_torrent(%Torrent{hash: "h1", name: "T1", label: "beta"})
      Store.put_torrent(%Torrent{hash: "h2", name: "T2", label: "alpha"})
      Store.put_torrent(%Torrent{hash: "h3", name: "T3", label: "beta"})

      assert Commands.get_all_labels() == ["alpha", "beta"]
    end

    test "excludes nil labels" do
      Store.put_torrent(%Torrent{hash: "h1", name: "T1", label: nil})
      Store.put_torrent(%Torrent{hash: "h2", name: "T2", label: "work"})

      assert Commands.get_all_labels() == ["work"]
    end

    test "returns empty list when no torrents have labels" do
      Store.put_torrent(%Torrent{hash: "h1", name: "T1", label: nil})

      assert Commands.get_all_labels() == []
    end

    test "returns empty list when store is empty" do
      assert Commands.get_all_labels() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3 — load_url/2 and load_raw/2 with opts
  # ---------------------------------------------------------------------------

  describe "load_url/2" do
    test "calls load.start without post-load commands when no opts" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.start", ["", url] ->
        assert url == "magnet:?xt=urn:btih:abc"
        {:ok, 0}
      end)

      assert Commands.load_url("magnet:?xt=urn:btih:abc") == :ok
    end

    test "appends d.custom1.set when label opt provided" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.start", ["", _url, post_cmd] ->
        assert post_cmd == "d.custom1.set=Linux"
        {:ok, 0}
      end)

      assert Commands.load_url("magnet:?xt=urn:btih:abc", label: "Linux") == :ok
    end

    test "appends d.directory_base.set when directory opt provided" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.start", ["", _url, post_cmd] ->
        assert post_cmd == "d.directory_base.set=/downloads/linux"
        {:ok, 0}
      end)

      assert Commands.load_url("magnet:?xt=urn:btih:abc", directory: "/downloads/linux") == :ok
    end

    test "appends both commands when label and directory opts provided" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.start", args ->
        assert args == [
                 "",
                 "magnet:?xt=urn:btih:abc",
                 "d.custom1.set=Linux",
                 "d.directory_base.set=/dl"
               ]

        {:ok, 0}
      end)

      assert Commands.load_url("magnet:?xt=urn:btih:abc", label: "Linux", directory: "/dl") ==
               :ok
    end
  end

  describe "load_raw/2" do
    test "appends d.custom1.set when label opt provided" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.raw_start",
                                               ["", {:base64, _data}, post_cmd] ->
        assert post_cmd == "d.custom1.set=Linux"
        {:ok, 0}
      end)

      assert Commands.load_raw(<<"binary">>, label: "Linux") == :ok
    end

    test "appends d.directory_base.set when directory opt provided" do
      expect(Taniwha.RPC.MockClient, :call, fn "load.raw_start",
                                               ["", {:base64, _data}, post_cmd] ->
        assert post_cmd == "d.directory_base.set=/downloads"
        {:ok, 0}
      end)

      assert Commands.load_raw(<<"binary">>, directory: "/downloads") == :ok
    end
  end
end
