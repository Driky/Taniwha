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

  @spec menu_label(:download | :upload) :: String.t()
  defp menu_label(:download), do: "Download limit"
  defp menu_label(:upload), do: "Upload limit"
end
