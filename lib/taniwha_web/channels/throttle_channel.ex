defmodule TaniwhaWeb.ThrottleChannel do
  @moduledoc """
  Phoenix Channel for bandwidth throttle settings.

  Clients join `"throttle:settings"` to receive and modify bandwidth limits and
  speed presets. On join the channel subscribes to the matching PubSub topic and
  returns the current state so the client starts with fresh data and receives
  incremental updates thereafter.

  ## Client → Server events

    * `"set_download_limit"` – set the global download limit in bytes/s
      (`%{"limit" => non_neg_integer()}`)
    * `"set_upload_limit"` – set the global upload limit in bytes/s
      (`%{"limit" => non_neg_integer()}`)
    * `"set_presets"` – replace the preset list
      (`%{"presets" => [%{"value" => pos_integer(), "unit" => "kib_s" | "mib_s"}]}`)

  ## Server → Client events

    * `"throttle_updated"` – limits changed
      (`%{"download_limit" => integer(), "upload_limit" => integer()}`)
    * `"presets_updated"` – presets changed
      (`%{"presets" => [%{"value" => integer(), "unit" => string(), "label" => string()}]}`)
  """

  use TaniwhaWeb, :channel

  alias Taniwha.ThrottleStore

  @valid_units ["kib_s", "mib_s"]

  # ---------------------------------------------------------------------------
  # Join
  # ---------------------------------------------------------------------------

  @doc """
  Join handler for `"throttle:settings"`.

  Subscribes to PubSub and returns the current download limit, upload limit,
  and preset list with string keys.
  """
  @impl true
  def join("throttle:settings", _payload, socket) do
    :ok = Phoenix.PubSub.subscribe(Taniwha.PubSub, "throttle:settings")

    reply = %{
      "download_limit" => ThrottleStore.get_download_limit(),
      "upload_limit" => ThrottleStore.get_upload_limit(),
      "presets" => serialize_presets(ThrottleStore.get_presets())
    }

    {:ok, reply, socket}
  end

  # ---------------------------------------------------------------------------
  # Command handlers
  # ---------------------------------------------------------------------------

  @doc """
  Sets the global download speed limit in bytes/s.

  Payload: `%{"limit" => non_neg_integer()}`. Rejects negative or non-integer
  values before reaching ThrottleStore.
  """
  @impl true
  def handle_in("set_download_limit", %{"limit" => limit}, socket)
      when is_integer(limit) and limit >= 0 do
    case ThrottleStore.set_download_limit(limit) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{"reason" => throttle_error_reason(reason)}}, socket}
    end
  end

  def handle_in("set_download_limit", _payload, socket) do
    {:reply, {:error, %{"reason" => "limit must be a non-negative integer"}}, socket}
  end

  def handle_in("set_upload_limit", %{"limit" => limit}, socket)
      when is_integer(limit) and limit >= 0 do
    case ThrottleStore.set_upload_limit(limit) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{"reason" => throttle_error_reason(reason)}}, socket}
    end
  end

  def handle_in("set_upload_limit", _payload, socket) do
    {:reply, {:error, %{"reason" => "limit must be a non-negative integer"}}, socket}
  end

  def handle_in("set_presets", %{"presets" => []}, socket) do
    {:reply, {:error, %{"reason" => "preset list must not be empty"}}, socket}
  end

  def handle_in("set_presets", %{"presets" => presets}, socket) when is_list(presets) do
    case validate_and_transform_presets(presets) do
      {:ok, transformed} ->
        case ThrottleStore.set_presets(transformed) do
          :ok ->
            {:reply, :ok, socket}

          {:error, reason} ->
            {:reply, {:error, %{"reason" => throttle_error_reason(reason)}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  def handle_in("set_presets", _payload, socket) do
    {:reply, {:error, %{"reason" => "presets must be a list"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub handle_info
  # ---------------------------------------------------------------------------

  @doc """
  Forwards PubSub broadcasts to the connected client.

  - `{:throttle_updated, limits}` → pushes `"throttle_updated"` with current limits
  - `{:presets_updated, presets}` → pushes `"presets_updated"` with serialized preset list
  """
  @impl true
  def handle_info({:throttle_updated, %{download_limit: dl, upload_limit: ul}}, socket) do
    push(socket, "throttle_updated", %{"download_limit" => dl, "upload_limit" => ul})
    {:noreply, socket}
  end

  def handle_info({:presets_updated, presets}, socket) do
    push(socket, "presets_updated", %{"presets" => serialize_presets(presets)})
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec serialize_presets([ThrottleStore.preset()]) :: [map()]
  defp serialize_presets(presets) do
    Enum.map(presets, fn %{value: v, unit: u, label: l} ->
      %{"value" => v, "unit" => Atom.to_string(u), "label" => l}
    end)
  end

  @spec unit_label(String.t()) :: String.t()
  defp unit_label("kib_s"), do: "KiB/s"
  defp unit_label("mib_s"), do: "MiB/s"

  @spec validate_and_transform_presets([map()]) ::
          {:ok, [ThrottleStore.preset()]} | {:error, String.t()}
  defp validate_and_transform_presets(presets) do
    result =
      Enum.reduce_while(presets, {:ok, []}, fn preset, {:ok, acc} ->
        with %{"value" => value, "unit" => unit} <- preset,
             true <- is_integer(value) and value > 0,
             true <- unit in @valid_units do
          atom_unit = String.to_existing_atom(unit)
          label = "#{value} #{unit_label(unit)}"
          {:cont, {:ok, [%{value: value, unit: atom_unit, label: label} | acc]}}
        else
          _ ->
            {:halt,
             {:error, "each preset must have a positive integer value and unit of kib_s or mib_s"}}
        end
      end)

    case result do
      {:ok, transformed} -> {:ok, Enum.reverse(transformed)}
      error -> error
    end
  end

  @spec throttle_error_reason(atom()) :: String.t()
  defp throttle_error_reason(:invalid_unit), do: "invalid unit"
  defp throttle_error_reason(:invalid_value), do: "preset value must be a positive integer"
  defp throttle_error_reason(:duplicate_preset), do: "duplicate preset after byte normalisation"
  defp throttle_error_reason(reason), do: inspect(reason)
end
