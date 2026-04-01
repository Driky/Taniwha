defmodule TaniwhaWeb.ThrottleChannelTest do
  @moduledoc false

  use TaniwhaWeb.ChannelCase, async: false

  alias Taniwha.{MockCommands, ThrottleStore}
  alias TaniwhaWeb.{ThrottleChannel, UserSocket}

  setup do
    {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    ThrottleStore.reset()
    on_exit(fn -> ThrottleStore.reset() end)
    {:ok, socket: socket}
  end

  # ---------------------------------------------------------------------------
  # Batch 1: Join
  # ---------------------------------------------------------------------------

  describe "join throttle:settings" do
    test "returns current limits and presets", %{socket: socket} do
      {:ok, reply, _channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")

      assert reply["download_limit"] == 0
      assert reply["upload_limit"] == 0
      assert is_list(reply["presets"])
      assert length(reply["presets"]) > 0
    end

    test "join returns string keys in presets", %{socket: socket} do
      {:ok, reply, _channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")

      assert [first | _] = reply["presets"]
      assert Map.has_key?(first, "value")
      assert Map.has_key?(first, "unit")
      assert Map.has_key?(first, "label")
      assert is_integer(first["value"])
      assert is_binary(first["unit"])
      assert is_binary(first["label"])
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 2: set_download_limit / set_upload_limit happy path
  # ---------------------------------------------------------------------------

  describe "set_download_limit" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "with valid payload replies :ok and pushes throttle_updated", %{channel: channel} do
      expect(MockCommands, :set_download_limit, fn 1_048_576 -> :ok end)

      ref = push(channel, "set_download_limit", %{"limit" => 1_048_576})

      assert_reply ref, :ok
      assert_push "throttle_updated", %{"download_limit" => 1_048_576, "upload_limit" => 0}
    end
  end

  describe "set_upload_limit" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "with valid payload replies :ok and pushes throttle_updated", %{channel: channel} do
      expect(MockCommands, :set_upload_limit, fn 524_288 -> :ok end)

      ref = push(channel, "set_upload_limit", %{"limit" => 524_288})

      assert_reply ref, :ok
      assert_push "throttle_updated", %{"download_limit" => 0, "upload_limit" => 524_288}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 3: limit validation failures
  # ---------------------------------------------------------------------------

  describe "set_download_limit validation" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "with negative value replies {:error, reason}", %{channel: channel} do
      ref = push(channel, "set_download_limit", %{"limit" => -1})
      assert_reply ref, :error, %{"reason" => _reason}
    end

    test "with non-integer value replies {:error, reason}", %{channel: channel} do
      ref = push(channel, "set_download_limit", %{"limit" => "fast"})
      assert_reply ref, :error, %{"reason" => _reason}
    end
  end

  describe "set_upload_limit validation" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "with negative value replies {:error, reason}", %{channel: channel} do
      ref = push(channel, "set_upload_limit", %{"limit" => -100})
      assert_reply ref, :error, %{"reason" => _reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 4: set_presets happy path
  # ---------------------------------------------------------------------------

  describe "set_presets" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "with valid list replies :ok and pushes presets_updated", %{channel: channel} do
      presets = [
        %{"value" => 5, "unit" => "mib_s"},
        %{"value" => 512, "unit" => "kib_s"}
      ]

      ref = push(channel, "set_presets", %{"presets" => presets})

      assert_reply ref, :ok

      assert_push "presets_updated", %{"presets" => pushed_presets}
      assert length(pushed_presets) == 2

      [first, second] = pushed_presets
      assert first["value"] == 5
      assert first["unit"] == "mib_s"
      assert first["label"] == "5 MiB/s"
      assert second["value"] == 512
      assert second["unit"] == "kib_s"
      assert second["label"] == "512 KiB/s"
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 5: set_presets validation failures
  # ---------------------------------------------------------------------------

  describe "set_presets validation" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "with empty list replies {:error, reason}", %{channel: channel} do
      ref = push(channel, "set_presets", %{"presets" => []})
      assert_reply ref, :error, %{"reason" => _reason}
    end

    test "with invalid unit replies {:error, reason}", %{channel: channel} do
      presets = [%{"value" => 5, "unit" => "gb_s"}]
      ref = push(channel, "set_presets", %{"presets" => presets})
      assert_reply ref, :error, %{"reason" => _reason}
    end

    test "with duplicate entries (after byte normalisation) replies {:error, reason}", %{
      channel: channel
    } do
      # 1024 kib_s == 1 mib_s → duplicate after byte normalisation
      presets = [
        %{"value" => 1, "unit" => "mib_s"},
        %{"value" => 1024, "unit" => "kib_s"}
      ]

      ref = push(channel, "set_presets", %{"presets" => presets})
      assert_reply ref, :error, %{"reason" => _reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Batch 6: PubSub handle_info pushes
  # ---------------------------------------------------------------------------

  describe "PubSub handle_info pushes" do
    setup %{socket: socket} do
      {:ok, _reply, channel} = subscribe_and_join(socket, ThrottleChannel, "throttle:settings")
      {:ok, channel: channel}
    end

    test "throttle_updated PubSub message pushes throttle_updated to client", %{channel: channel} do
      send(
        channel.channel_pid,
        {:throttle_updated, %{download_limit: 2_097_152, upload_limit: 1_048_576}}
      )

      assert_push "throttle_updated", %{
        "download_limit" => 2_097_152,
        "upload_limit" => 1_048_576
      }
    end

    test "presets_updated PubSub message pushes presets_updated to client", %{channel: channel} do
      presets = [
        %{value: 5, unit: :mib_s, label: "5 MiB/s"},
        %{value: 512, unit: :kib_s, label: "512 KiB/s"}
      ]

      send(channel.channel_pid, {:presets_updated, presets})

      assert_push "presets_updated", %{"presets" => pushed_presets}
      assert length(pushed_presets) == 2

      [first, second] = pushed_presets
      assert first["value"] == 5
      assert first["unit"] == "mib_s"
      assert first["label"] == "5 MiB/s"
      assert second["value"] == 512
      assert second["unit"] == "kib_s"
      assert second["label"] == "512 KiB/s"
    end
  end
end
