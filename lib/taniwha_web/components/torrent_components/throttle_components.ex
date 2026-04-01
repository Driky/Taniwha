defmodule TaniwhaWeb.TorrentComponents.ThrottleComponents do
  @moduledoc "Speed limit context menu component for the topbar bandwidth indicators."

  use TaniwhaWeb, :html
  alias Taniwha.ThrottleStore

  @doc """
  Renders the bandwidth limit context menu anchored below the speed indicator.

  ## Attributes

  - `:direction` (required) — `:download` or `:upload`
  - `:current_limit` (required) — bytes/s, `0` = unlimited
  - `:presets` (required) — list of preset maps
  - `:custom_input` — whether the custom limit form is shown, default `false`
  """
  attr :direction, :atom, required: true
  attr :current_limit, :integer, required: true
  attr :presets, :list, required: true
  attr :custom_input, :boolean, default: false

  def throttle_context_menu(assigns) do
    ~H"""
    <div
      role="menu"
      id={"throttle-menu-#{@direction}"}
      aria-label={menu_label(@direction)}
      phx-hook="ThrottleFocus"
      class="absolute top-full right-0 z-50 mt-1 p-1 w-52 rounded-lg shadow-2xl
             bg-white border border-gray-200
             dark:bg-[#1a1f2e] dark:border-gray-600"
    >
      <div class="text-[10px] font-semibold uppercase tracking-[0.08em] px-3 pt-1.5 pb-1
                  text-gray-400 dark:text-gray-500 select-none">
        {menu_label(@direction)}
      </div>
      <div class="max-h-60 overflow-y-auto">
        <.limit_item
          label="Unlimited"
          bytes={0}
          current_limit={@current_limit}
          direction={@direction}
        />
        <.limit_item
          :for={preset <- @presets}
          label={preset.label}
          bytes={ThrottleStore.preset_to_bytes(preset)}
          current_limit={@current_limit}
          direction={@direction}
        />
      </div>
      <div class="border-t my-1 border-gray-100 dark:border-[#2d3748]" />
      <%= if @custom_input do %>
        <.custom_form direction={@direction} />
      <% else %>
        <button
          role="menuitem"
          type="button"
          phx-click="show_custom_input"
          phx-value-direction={Atom.to_string(@direction)}
          class="text-[11px] px-3 py-[5px] rounded w-full flex items-center gap-2 text-left
                 cursor-pointer bg-transparent border-none text-gray-700 dark:text-gray-400"
        >
          <span class="w-3 h-3 flex-shrink-0 inline-block" /> Custom…
        </button>
      <% end %>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :bytes, :integer, required: true
  attr :current_limit, :integer, required: true
  attr :direction, :atom, required: true

  defp limit_item(assigns) do
    assigns = assign(assigns, :active, assigns.current_limit == assigns.bytes)

    ~H"""
    <button
      role="menuitemradio"
      aria-checked={to_string(@active)}
      type="button"
      phx-click="set_throttle_limit"
      phx-value-direction={Atom.to_string(@direction)}
      phx-value-bytes={to_string(@bytes)}
      class={[
        "text-[11px] px-3 py-[5px] rounded w-full flex items-center gap-2 text-left cursor-pointer border-none",
        if(@active,
          do: "bg-gray-100 text-gray-900 dark:bg-[#2d3748] dark:text-gray-200",
          else: "bg-transparent text-gray-700 dark:text-gray-400"
        )
      ]}
    >
      <%= if @active do %>
        <svg
          class="w-3 h-3 flex-shrink-0"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="2.5"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M5 13l4 4L19 7"
            class="stroke-blue-600 dark:stroke-blue-400"
          />
        </svg>
      <% else %>
        <span class="w-3 h-3 flex-shrink-0 inline-block" aria-hidden="true" />
      <% end %>
      {@label}
    </button>
    """
  end

  attr :direction, :atom, required: true

  defp custom_form(assigns) do
    ~H"""
    <form phx-submit="apply_custom_limit" class="px-2 pt-1 pb-1.5 flex items-center gap-1">
      <input type="hidden" name="direction" value={Atom.to_string(@direction)} />
      <input
        type="text"
        name="value"
        placeholder="e.g. 5"
        phx-hook="ThrottleFocusInput"
        id={"throttle-custom-value-#{@direction}"}
        class="w-[52px] h-6 px-1.5 text-[11px] rounded-[5px] text-right outline-none
               border border-gray-300 bg-white text-gray-700
               dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300"
      />
      <select
        name="unit"
        class="h-6 px-1 text-[11px] rounded-[5px] cursor-pointer outline-none
               border border-gray-300 bg-white text-gray-700
               dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300"
      >
        <option value="mib_s">MiB/s</option>
        <option value="kib_s">KiB/s</option>
      </select>
      <button
        type="submit"
        class="h-6 px-2 text-[11px] font-medium bg-blue-600 text-white
               border-none rounded-[5px] cursor-pointer"
      >
        Set
      </button>
    </form>
    """
  end

  @doc """
  Renders the preset list editor used in the Settings page.

  ## Attributes

  - `:presets` (required) — list of preset maps (already sorted ascending by bytes)
  - `:new_value` (required) — current value string in the add-preset input
  - `:new_unit` (required) — current unit selection (`"mib_s"` or `"kib_s"`)
  - `:error` — validation error string or `nil`
  """
  attr :presets, :list, required: true
  attr :new_value, :string, required: true
  attr :new_unit, :string, required: true
  attr :error, :string, default: nil

  def preset_editor(assigns) do
    ~H"""
    <%!-- Preset list --%>
    <ul role="list" class="border-t border-gray-100 dark:border-[#2d3748] mt-3">
      <li
        :for={{preset, idx} <- Enum.with_index(@presets)}
        class="border-b border-gray-100 dark:border-[#2d3748] px-4 py-[10px] flex items-center gap-2.5"
      >
        <svg
          class="w-3.5 h-3.5 flex-shrink-0"
          fill="none"
          stroke="#9ca3af"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M13 10V3L4 14h7v7l9-11h-7z"
          />
        </svg>
        <span class="flex-1 text-[11px] font-medium text-gray-900 dark:text-gray-100">
          {preset.label}
        </span>
        <button
          type="button"
          phx-click="remove_preset"
          phx-value-index={idx}
          aria-label={"Remove #{preset.label} preset"}
          class="w-[26px] h-[26px] rounded border-none bg-transparent cursor-pointer
                 flex items-center justify-center opacity-40 hover:opacity-100 transition-opacity"
        >
          <svg
            class="w-[13px] h-[13px]"
            fill="none"
            stroke="#ef4444"
            viewBox="0 0 24 24"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858
                 L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
            />
          </svg>
        </button>
      </li>
    </ul>
    <%!-- Add preset footer --%>
    <div class="px-4 py-[10px] border-t border-gray-100 dark:border-[#2d3748]">
      <label
        for="preset-value-input"
        class="text-[11px] font-medium text-gray-700 dark:text-gray-300 block mb-1.5"
      >
        Add preset
      </label>
      <form phx-submit="add_preset" class="flex items-center gap-1.5">
        <input
          id="preset-value-input"
          type="text"
          name="value"
          value={@new_value}
          placeholder="e.g., 5"
          phx-change="update_new_preset"
          aria-label="Speed value"
          aria-describedby={if @error, do: "preset-error", else: nil}
          class="w-16 h-[26px] px-2 text-[11px] border border-gray-200 dark:border-gray-700
                 rounded-md bg-white dark:bg-gray-900 text-gray-700 dark:text-gray-300
                 outline-none text-right"
        />
        <select
          name="unit"
          aria-label="Unit"
          phx-change="update_new_unit"
          class="h-[26px] px-1.5 text-[11px] border border-gray-200 dark:border-gray-700
                 rounded-md bg-white dark:bg-gray-900 text-gray-700 dark:text-gray-300
                 outline-none cursor-pointer"
        >
          <option value="mib_s" selected={@new_unit == "mib_s"}>MiB/s</option>
          <option value="kib_s" selected={@new_unit == "kib_s"}>KiB/s</option>
        </select>
        <button
          type="submit"
          class="h-[26px] px-3 text-[11px] font-medium bg-blue-600 text-white
                 border-none rounded-md cursor-pointer"
        >
          Add
        </button>
      </form>
      <p :if={@error} id="preset-error" role="alert" class="mt-1.5 text-[10px] text-red-500">
        {@error}
      </p>
    </div>
    """
  end

  @spec menu_label(:download | :upload) :: String.t()
  defp menu_label(:download), do: "Download limit"
  defp menu_label(:upload), do: "Upload limit"
end
