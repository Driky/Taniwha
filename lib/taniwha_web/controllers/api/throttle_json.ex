defmodule TaniwhaWeb.API.ThrottleJSON do
  @moduledoc """
  JSON rendering for throttle responses.
  """

  @doc "Renders the current bandwidth settings."
  @spec show(map()) :: map()
  def show(%{download_limit: dl, upload_limit: ul, presets: presets}) do
    %{"download_limit" => dl, "upload_limit" => ul, "presets" => Enum.map(presets, &preset/1)}
  end

  @doc "Renders an updated preset list."
  @spec set_presets(map()) :: map()
  def set_presets(%{presets: presets}), do: %{"presets" => Enum.map(presets, &preset/1)}

  @spec preset(map()) :: map()
  defp preset(%{value: v, unit: u, label: l}),
    do: %{"value" => v, "unit" => Atom.to_string(u), "label" => l}
end
