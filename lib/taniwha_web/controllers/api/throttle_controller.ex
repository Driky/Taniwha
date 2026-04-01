defmodule TaniwhaWeb.API.ThrottleController do
  @moduledoc """
  REST endpoints for bandwidth throttle settings.

  Reads state from `Taniwha.ThrottleStore` via the ETS fast path and delegates
  mutations through the same store (which serialises writes via its GenServer
  mailbox and calls `Taniwha.Commands` internally). This controller never calls
  `Taniwha.Commands` directly.
  """

  use TaniwhaWeb, :controller

  alias Taniwha.ThrottleStore

  @valid_units ["kib_s", "mib_s"]

  @doc "Returns the current download limit, upload limit, and preset list."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    render(conn, :show,
      download_limit: ThrottleStore.get_download_limit(),
      upload_limit: ThrottleStore.get_upload_limit(),
      presets: ThrottleStore.get_presets()
    )
  end

  @doc """
  Sets the global download speed limit in bytes/s.

  Accepts `%{"limit" => non_neg_integer()}`. Returns 204 on success, 422 for
  invalid input, 503 if rtorrent is unreachable.
  """
  @spec set_download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_download(conn, %{"limit" => limit}) when is_integer(limit) and limit >= 0 do
    case ThrottleStore.set_download_limit(limit) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> conn |> put_status(503) |> json(%{error: inspect(reason)})
    end
  end

  def set_download(conn, _params) do
    conn |> put_status(422) |> json(%{error: "limit must be a non-negative integer"})
  end

  @doc """
  Sets the global upload speed limit in bytes/s.

  Same semantics as `set_download/2`.
  """
  @spec set_upload(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_upload(conn, %{"limit" => limit}) when is_integer(limit) and limit >= 0 do
    case ThrottleStore.set_upload_limit(limit) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> conn |> put_status(503) |> json(%{error: inspect(reason)})
    end
  end

  def set_upload(conn, _params) do
    conn |> put_status(422) |> json(%{error: "limit must be a non-negative integer"})
  end

  @doc """
  Replaces the preset list.

  Accepts `%{"presets" => [%{"value" => pos_integer(), "unit" => "kib_s" | "mib_s"}]}`.
  Validates each preset, checks for duplicates after byte normalisation, sorts by
  bytes ascending, and returns the stored list. Returns 200 with sorted presets on
  success, 422 for validation errors, 503 if the store operation fails.
  """
  @spec set_presets(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_presets(conn, %{"presets" => []}) do
    conn |> put_status(422) |> json(%{error: "preset list must not be empty"})
  end

  def set_presets(conn, %{"presets" => presets}) when is_list(presets) do
    case validate_and_transform_presets(presets) do
      {:ok, transformed} ->
        sorted = Enum.sort_by(transformed, &ThrottleStore.preset_to_bytes/1)

        case ThrottleStore.set_presets(sorted) do
          :ok -> render(conn, :set_presets, presets: sorted)
          {:error, reason} -> conn |> put_status(503) |> json(%{error: inspect(reason)})
        end

      {:error, message} ->
        conn |> put_status(422) |> json(%{error: message})
    end
  end

  def set_presets(conn, _params) do
    conn |> put_status(422) |> json(%{error: "presets must be a list"})
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

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
      {:ok, transformed} ->
        transformed = Enum.reverse(transformed)
        bytes_list = Enum.map(transformed, &ThrottleStore.preset_to_bytes/1)

        if Enum.uniq(bytes_list) == bytes_list do
          {:ok, transformed}
        else
          {:error, "duplicate preset after byte normalisation"}
        end

      error ->
        error
    end
  end

  @spec unit_label(String.t()) :: String.t()
  defp unit_label("kib_s"), do: "KiB/s"
  defp unit_label("mib_s"), do: "MiB/s"
end
