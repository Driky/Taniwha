defmodule Taniwha.ThrottleStoreTest do
  @moduledoc false
  use ExUnit.Case, async: false

  import Mox

  alias Taniwha.ThrottleStore

  setup :set_mox_global
  setup :verify_on_exit!

  # Provide default stubs for startup RPC calls so that isolated ThrottleStore
  # instances (started in init tests) don't trigger Mox.UnexpectedCallError.
  # Tests that need specific behaviour can override with expect/3.
  setup do
    Mox.stub(Taniwha.MockCommands, :set_download_limit, fn _ -> :ok end)
    Mox.stub(Taniwha.MockCommands, :set_upload_limit, fn _ -> :ok end)
    # Prevent spurious calls from the global store's sync timer (disabled in test
    # env via config, but isolated stores started with sync_interval: 50 need stubs).
    Mox.stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 0} end)
    Mox.stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)
    ThrottleStore.reset()
    :ok
  end

  # ── Helpers for isolated init tests ────────────────────────────────────────

  defp unique_table do
    :"taniwha_throttle_test_#{:erlang.unique_integer([:positive])}"
  end

  # Starts an isolated ThrottleStore with a unique ETS table name.
  # Used only for tests that need to exercise init logic.
  # Returns {pid, file_path, table_name}.
  defp start_isolated_store(opts \\ []) do
    tmp_path =
      Path.join(
        System.tmp_dir!(),
        "throttle_#{:erlang.unique_integer([:positive])}.json"
      )

    table = unique_table()
    merged = Keyword.merge([file_path: tmp_path, ets_table: table, name: false], opts)
    {:ok, pid} = GenServer.start_link(ThrottleStore, merged)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
      File.rm(tmp_path)
      File.rm(tmp_path <> ".tmp")
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end)

    {pid, tmp_path, table}
  end

  # ── Batch 1: pure unit-conversion helpers ──────────────────────────────────

  describe "preset_to_bytes/1" do
    test "converts MiB/s preset to bytes" do
      assert ThrottleStore.preset_to_bytes(%{value: 5, unit: :mib_s}) == 5_242_880
    end

    test "converts KiB/s preset to bytes" do
      assert ThrottleStore.preset_to_bytes(%{value: 512, unit: :kib_s}) == 524_288
    end
  end

  describe "bytes_to_display/1" do
    test "0 returns Unlimited" do
      assert ThrottleStore.bytes_to_display(0) == "Unlimited"
    end

    test "aligned MiB/s renders as integer" do
      assert ThrottleStore.bytes_to_display(5_242_880) == "5 MiB/s"
    end

    test "aligned KiB/s renders as integer" do
      assert ThrottleStore.bytes_to_display(524_288) == "512 KiB/s"
    end

    test "non-aligned renders with 1 decimal place" do
      assert ThrottleStore.bytes_to_display(1_500_000) == "1.4 MiB/s"
    end
  end

  # ── Batch 2: init with no JSON file ───────────────────────────────────────

  describe "init/1 with no JSON file" do
    test "ETS contains download_limit: 0 and upload_limit: 0" do
      {_pid, _path, table} = start_isolated_store()

      assert :ets.lookup_element(table, :download_limit, 2) == 0
      assert :ets.lookup_element(table, :upload_limit, 2) == 0
    end

    test "ETS contains default presets" do
      {_pid, _path, table} = start_isolated_store()
      presets = :ets.lookup_element(table, :presets, 2)

      assert is_list(presets)
      assert length(presets) > 0
      assert Enum.all?(presets, &(Map.has_key?(&1, :value) and Map.has_key?(&1, :unit)))
    end

    test "a JSON file is written with defaults" do
      {_pid, path, _table} = start_isolated_store()

      assert File.exists?(path)
      {:ok, json} = File.read(path)
      {:ok, data} = Jason.decode(json)
      assert data["version"] == 1
      assert data["download_limit"] == 0
      assert data["upload_limit"] == 0
      assert is_list(data["presets"])
    end
  end

  # ── Batch 3: init from existing JSON file ─────────────────────────────────

  describe "init/1 with valid JSON file" do
    test "ETS is populated from file with custom limits and presets" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "throttle_existing_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      saved_presets = [%{"value" => 8, "unit" => "mib_s", "label" => "8 MiB/s"}]

      File.write!(
        tmp_path,
        Jason.encode!(%{
          "version" => 1,
          "download_limit" => 3_000_000,
          "upload_limit" => 1_000_000,
          "presets" => saved_presets
        })
      )

      table = unique_table()

      expect(Taniwha.MockCommands, :set_download_limit, fn 3_000_000 -> :ok end)
      expect(Taniwha.MockCommands, :set_upload_limit, fn 1_000_000 -> :ok end)

      {:ok, pid} =
        GenServer.start_link(ThrottleStore,
          file_path: tmp_path,
          ets_table: table,
          name: false
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        if :ets.whereis(table) != :undefined, do: :ets.delete(table)
      end)

      assert :ets.lookup_element(table, :download_limit, 2) == 3_000_000
      assert :ets.lookup_element(table, :upload_limit, 2) == 1_000_000
      presets = :ets.lookup_element(table, :presets, 2)
      assert [%{value: 8, unit: :mib_s}] = presets
    end

    test "saved limits are applied to rtorrent via Commands on startup" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "throttle_apply_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)

      File.write!(
        tmp_path,
        Jason.encode!(%{
          "version" => 1,
          "download_limit" => 5_242_880,
          "upload_limit" => 2_097_152,
          "presets" => []
        })
      )

      table = unique_table()

      expect(Taniwha.MockCommands, :set_download_limit, fn 5_242_880 -> :ok end)
      expect(Taniwha.MockCommands, :set_upload_limit, fn 2_097_152 -> :ok end)

      {:ok, pid} =
        GenServer.start_link(ThrottleStore,
          file_path: tmp_path,
          ets_table: table,
          name: false
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        if :ets.whereis(table) != :undefined, do: :ets.delete(table)
      end)

      # verify_on_exit! ensures both expects above were called
    end
  end

  describe "init/1 with corrupt JSON file" do
    test "ETS uses defaults and a fresh file is written" do
      tmp_path =
        Path.join(
          System.tmp_dir!(),
          "throttle_corrupt_#{:erlang.unique_integer([:positive])}.json"
        )

      on_exit(fn -> File.rm(tmp_path) end)
      File.write!(tmp_path, "this is not valid JSON {{{")

      table = unique_table()

      {:ok, pid} =
        GenServer.start_link(ThrottleStore,
          file_path: tmp_path,
          ets_table: table,
          name: false
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        if :ets.whereis(table) != :undefined, do: :ets.delete(table)
      end)

      assert :ets.lookup_element(table, :download_limit, 2) == 0
      assert :ets.lookup_element(table, :upload_limit, 2) == 0

      {:ok, json} = File.read(tmp_path)
      {:ok, data} = Jason.decode(json)
      assert data["download_limit"] == 0
    end
  end

  # ── Batch 4: write operations (global store) ───────────────────────────────

  describe "set_download_limit/1" do
    test "updates ETS and broadcasts {:throttle_updated, map}" do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "throttle:settings")
      expect(Taniwha.MockCommands, :set_download_limit, fn 5_242_880 -> :ok end)

      assert :ok = ThrottleStore.set_download_limit(5_242_880)
      assert ThrottleStore.get_download_limit() == 5_242_880
      assert_receive {:throttle_updated, %{download_limit: 5_242_880}}, 1_000
    end

    test "does NOT update ETS if RPC fails" do
      expect(Taniwha.MockCommands, :set_download_limit, fn _ -> {:error, :timeout} end)

      assert {:error, :timeout} = ThrottleStore.set_download_limit(5_242_880)
      assert ThrottleStore.get_download_limit() == 0
    end

    test "persists to file on success" do
      file_path = Application.get_env(:taniwha, :throttle_settings_path)
      expect(Taniwha.MockCommands, :set_download_limit, fn 2_097_152 -> :ok end)

      :ok = ThrottleStore.set_download_limit(2_097_152)

      {:ok, json} = File.read(file_path)
      {:ok, data} = Jason.decode(json)
      assert data["download_limit"] == 2_097_152
    end
  end

  describe "set_upload_limit/1" do
    test "updates ETS and broadcasts {:throttle_updated, map}" do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "throttle:settings")
      expect(Taniwha.MockCommands, :set_upload_limit, fn 1_048_576 -> :ok end)

      assert :ok = ThrottleStore.set_upload_limit(1_048_576)
      assert ThrottleStore.get_upload_limit() == 1_048_576
      assert_receive {:throttle_updated, %{upload_limit: 1_048_576}}, 1_000
    end

    test "does NOT update ETS if RPC fails" do
      expect(Taniwha.MockCommands, :set_upload_limit, fn _ -> {:error, :econnrefused} end)

      assert {:error, :econnrefused} = ThrottleStore.set_upload_limit(1_048_576)
      assert ThrottleStore.get_upload_limit() == 0
    end
  end

  describe "get_download_limit/0 and get_upload_limit/0" do
    test "read directly from ETS without going through GenServer" do
      :ets.insert(:taniwha_throttle, {:download_limit, 99_999})
      :ets.insert(:taniwha_throttle, {:upload_limit, 77_777})

      assert ThrottleStore.get_download_limit() == 99_999
      assert ThrottleStore.get_upload_limit() == 77_777
    end
  end

  # ── Batch 5: preset operations ─────────────────────────────────────────────

  describe "set_presets/1" do
    test "updates ETS, persists to file, broadcasts {:presets_updated, presets}" do
      Phoenix.PubSub.subscribe(Taniwha.PubSub, "throttle:settings")
      presets = [%{value: 5, unit: :mib_s, label: "5 MiB/s"}]

      assert :ok = ThrottleStore.set_presets(presets)
      assert ThrottleStore.get_presets() == presets
      assert_receive {:presets_updated, ^presets}, 1_000
    end

    test "rejects presets with invalid units" do
      presets = [%{value: 5, unit: :gigabyte, label: "Bad"}]
      assert {:error, :invalid_unit} = ThrottleStore.set_presets(presets)
    end

    test "rejects presets with non-positive values" do
      presets = [%{value: 0, unit: :mib_s, label: "Zero"}]
      assert {:error, :invalid_value} = ThrottleStore.set_presets(presets)
    end

    test "rejects presets with duplicate byte values (e.g. 1 MiB/s = 1024 KiB/s)" do
      presets = [
        %{value: 1, unit: :mib_s, label: "1 MiB/s"},
        %{value: 1024, unit: :kib_s, label: "1024 KiB/s"}
      ]

      assert {:error, :duplicate_preset} = ThrottleStore.set_presets(presets)
    end
  end

  describe "get_presets/0" do
    test "reads from ETS (fast path)" do
      presets = [%{value: 3, unit: :mib_s, label: "3 MiB/s"}]
      :ok = ThrottleStore.set_presets(presets)
      assert ThrottleStore.get_presets() == presets
    end
  end

  # ── Batch 6: sync_limits polling ──────────────────────────────────────────

  describe "sync_limits polling" do
    # Starts an isolated store with a fast sync interval.
    defp start_sync_store(opts \\ []) do
      start_isolated_store(Keyword.merge([sync_interval: 50], opts))
    end

    test "updates ETS and broadcasts when rtorrent returns different limits" do
      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 0} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)
      {_pid, _path, table} = start_sync_store()

      Phoenix.PubSub.subscribe(Taniwha.PubSub, "throttle:settings")

      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 3_145_728} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 1_048_576} end)

      assert_receive {:throttle_updated, %{download_limit: 3_145_728, upload_limit: 1_048_576}},
                     500

      assert :ets.lookup_element(table, :download_limit, 2) == 3_145_728
      assert :ets.lookup_element(table, :upload_limit, 2) == 1_048_576
    end

    test "does not broadcast when rtorrent returns the same limits" do
      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 0} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)
      {_pid, _path, _table} = start_sync_store()

      Phoenix.PubSub.subscribe(Taniwha.PubSub, "throttle:settings")

      refute_receive {:throttle_updated, _}, 200
    end

    test "persists changed limits to file" do
      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 0} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)
      {_pid, path, _table} = start_sync_store()

      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 2_097_152} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)

      :timer.sleep(200)

      {:ok, json} = File.read(path)
      {:ok, data} = Jason.decode(json)
      assert data["download_limit"] == 2_097_152
    end

    test "does not crash when Commands returns an error" do
      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:error, :timeout} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)
      {pid, _path, _table} = start_sync_store()

      :timer.sleep(200)
      assert Process.alive?(pid)
    end

    test "continues polling after an error" do
      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:error, :timeout} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)
      {pid, _path, table} = start_sync_store()

      :timer.sleep(100)

      stub(Taniwha.MockCommands, :get_download_limit, fn -> {:ok, 5_242_880} end)
      stub(Taniwha.MockCommands, :get_upload_limit, fn -> {:ok, 0} end)

      :timer.sleep(200)
      assert :ets.lookup_element(table, :download_limit, 2) == 5_242_880
      assert Process.alive?(pid)
    end
  end
end
