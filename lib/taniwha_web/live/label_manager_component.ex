defmodule TaniwhaWeb.LabelManagerComponent do
  @moduledoc """
  LiveComponent for the "Manage Labels" modal overlay.

  Rendered inside `DashboardLive` when `@show_label_manager` is true. Lists
  all existing labels (derived from the ETS torrent cache) with their torrent
  counts, and allows creating, renaming, and deleting labels.

  Label colour metadata is stored in `Taniwha.LabelStore` and persisted to
  disk. Renaming a label calls `Commands.rename_label/2` which issues one
  `d.custom1.set` RPC call per affected torrent.
  """

  use TaniwhaWeb, :live_component

  alias Taniwha.LabelStore

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  @palette [
    "#ec4899",
    "#6366f1",
    "#a855f7",
    "#22c55e",
    "#3b82f6",
    "#f59e0b"
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing, nil)
     |> assign(:new_name, "")
     |> assign(:new_color, List.first(@palette))
     |> assign(:edit_name, "")
     |> assign(:edit_color, List.first(@palette))}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("close", _params, socket) do
    send(self(), {:hide_label_manager})
    {:noreply, socket}
  end

  def handle_event("create_label", %{"label_name" => name, "color" => color}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, socket}
    else
      {_, bg, text} = palette_triplet(color)
      LabelStore.set_color(name, color, bg, text)
      send(self(), {:label_created, name})
      {:noreply, assign(socket, :new_name, "")}
    end
  end

  def handle_event("delete_label", %{"label" => label}, socket) do
    affected =
      Taniwha.State.Store.get_all_torrents()
      |> Enum.filter(&(&1.label == label))

    Enum.each(affected, fn t -> @commands.remove_label(t.hash) end)
    LabelStore.delete(label)
    send(self(), {:label_deleted, label})
    {:noreply, socket}
  end

  def handle_event("start_edit", %{"label" => label}, socket) do
    {dot, _bg, _text} = LabelStore.auto_assign(label)

    {:noreply,
     socket |> assign(:editing, label) |> assign(:edit_name, label) |> assign(:edit_color, dot)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("save_edit", %{"new_name" => new_name, "color" => color}, socket) do
    old_name = socket.assigns.editing
    new_name = String.trim(new_name)

    if new_name == "" do
      {:noreply, socket}
    else
      # Update colour in LabelStore
      {_, bg, text} = palette_triplet(color)

      if old_name != new_name do
        @commands.rename_label(old_name, new_name)
        LabelStore.delete(old_name)
      end

      LabelStore.set_color(new_name, color, bg, text)
      send(self(), {:label_renamed, old_name, new_name})
      {:noreply, assign(socket, :editing, nil)}
    end
  end

  @impl true
  def render(assigns) do
    label_groups = assigns[:label_groups] || []

    # Build display list: [{name, count, dot, bg, text}]
    display_labels =
      Enum.map(label_groups, fn {name, count} ->
        {dot, bg, text} = LabelStore.auto_assign(name)
        {name, count, dot, bg, text}
      end)

    assigns = assign(assigns, :display_labels, display_labels)
    assigns = assign(assigns, :palette, @palette)

    ~H"""
    <div id={@id} class="fixed inset-0 z-50">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/30 dark:bg-black/55"
        phx-click="close"
        phx-target={@myself}
        aria-hidden="true"
      />
      <%!-- Modal --%>
      <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
        <.focus_wrap
          id={"#{@id}-wrap"}
          phx-key="Escape"
          phx-window-keydown="close"
          phx-target={@myself}
          class="w-full max-w-[400px] mx-4 pointer-events-auto"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Labels"
            aria-labelledby={"#{@id}-title"}
            class="bg-white dark:bg-gray-800 rounded-[10px] border border-gray-200 dark:border-gray-700 shadow-[0_20px_60px_rgba(0,0,0,0.25)]"
          >
            <%!-- Header --%>
            <div class="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700">
              <h2
                id={"#{@id}-title"}
                class="text-[13px] font-semibold text-gray-900 dark:text-gray-50"
              >
                Labels
              </h2>
              <button
                type="button"
                phx-click="close"
                phx-target={@myself}
                aria-label="Close label manager"
                class="flex items-center justify-center size-5 text-gray-400 hover:text-gray-600 cursor-pointer border-none bg-transparent"
              >
                <.icon name="hero-x-mark-mini" class="size-4" />
              </button>
            </div>

            <%!-- Label list --%>
            <div class="py-1 max-h-[320px] overflow-y-auto">
              <%= if @display_labels == [] do %>
                <p
                  class="px-4 py-3 text-[11px] italic"
                  style="color: var(--taniwha-sidebar-section)"
                >
                  No labels yet
                </p>
              <% else %>
                <%= for {name, count, dot, _bg, _text} <- @display_labels do %>
                  <%= if @editing == name do %>
                    <%!-- Inline edit row --%>
                    <form
                      phx-submit="save_edit"
                      phx-target={@myself}
                      class="flex items-center gap-2 px-4 py-[6px]"
                    >
                      <input
                        type="text"
                        name="new_name"
                        value={@edit_name}
                        class="flex-1 h-[26px] px-2 text-[11px] border border-gray-300 dark:border-gray-600 rounded-[6px] bg-white dark:bg-gray-900 text-gray-700 dark:text-gray-300 focus:outline-none focus:ring-1 focus:ring-blue-500"
                        aria-label="New label name"
                      />
                      <%!-- Colour picker --%>
                      <div class="flex items-center gap-[3px]">
                        <%= for hex <- @palette do %>
                          <button
                            type="button"
                            phx-click="save_edit"
                            phx-target={@myself}
                            phx-value-color={hex}
                            phx-value-new_name={@edit_name}
                            class="size-[14px] rounded-full border-2 cursor-pointer"
                            style={"background: #{hex}; border-color: #{if @edit_color == hex, do: "color-mix(in srgb, #{hex}, black 30%)", else: "transparent"}"}
                            aria-label={"Select colour #{hex}"}
                          />
                        <% end %>
                      </div>
                      <input type="hidden" name="color" value={@edit_color} />
                      <button
                        type="submit"
                        class="h-[26px] px-2 text-[11px] font-medium bg-blue-600 text-white rounded-[6px] cursor-pointer hover:bg-blue-700 border-none"
                      >
                        Save
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_edit"
                        phx-target={@myself}
                        class="h-[26px] px-2 text-[11px] text-gray-500 border border-gray-200 dark:border-gray-600 rounded-[6px] cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-700 bg-white dark:bg-gray-800"
                      >
                        Cancel
                      </button>
                    </form>
                  <% else %>
                    <%!-- Normal row --%>
                    <div class="flex items-center gap-2 px-4 py-[6px]">
                      <span
                        class="size-2 rounded-full shrink-0"
                        style={"background-color: #{dot}"}
                        aria-hidden="true"
                      />
                      <span class="flex-1 text-[12px] text-gray-900 dark:text-gray-100">
                        {name}
                      </span>
                      <span class="text-[11px] mr-2" style="color: var(--taniwha-sidebar-section)">
                        {count}
                      </span>
                      <button
                        type="button"
                        phx-click="start_edit"
                        phx-target={@myself}
                        phx-value-label={name}
                        aria-label={"Edit label #{name}"}
                        class="flex items-center justify-center size-[22px] border border-gray-200 dark:border-gray-600 rounded-[4px] bg-white dark:bg-gray-800 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-700"
                      >
                        <.icon name="hero-pencil-micro" class="size-3 text-gray-500" />
                      </button>
                      <button
                        type="button"
                        phx-click="delete_label"
                        phx-target={@myself}
                        phx-value-label={name}
                        aria-label={"Delete label #{name}"}
                        class="flex items-center justify-center size-[22px] border border-gray-200 dark:border-gray-600 rounded-[4px] bg-white dark:bg-gray-800 cursor-pointer hover:bg-red-50 dark:hover:bg-red-900/20"
                      >
                        <.icon name="hero-trash-micro" class="size-3 text-red-500" />
                      </button>
                    </div>
                  <% end %>
                <% end %>
              <% end %>
            </div>

            <%!-- New label form --%>
            <div class="px-4 py-[10px] border-t border-gray-200 dark:border-gray-700">
              <p class="text-[11px] font-medium text-gray-700 dark:text-gray-300 mb-[6px]">
                New label
              </p>
              <form
                phx-submit="create_label"
                phx-target={@myself}
                class="flex items-center gap-[6px]"
              >
                <input
                  type="text"
                  name="label_name"
                  value={@new_name}
                  placeholder="Label name…"
                  class="flex-1 h-[26px] px-2 text-[11px] border border-gray-200 dark:border-gray-600 rounded-[6px] bg-white dark:bg-gray-900 text-gray-700 dark:text-gray-300 focus:outline-none focus:ring-1 focus:ring-blue-500"
                  aria-label="New label name"
                />
                <%!-- Colour picker --%>
                <div class="flex items-center gap-[3px]">
                  <%= for hex <- @palette do %>
                    <button
                      type="button"
                      phx-click="create_label"
                      phx-target={@myself}
                      phx-value-label_name={@new_name}
                      phx-value-color={hex}
                      class="size-[14px] rounded-full border-2 cursor-pointer"
                      style={"background: #{hex}; border-color: #{if @new_color == hex, do: "color-mix(in srgb, #{hex}, black 30%)", else: "transparent"}"}
                      aria-label={"Select colour #{hex}"}
                    />
                  <% end %>
                </div>
                <input type="hidden" name="color" value={@new_color} />
                <button
                  type="submit"
                  class="h-[26px] px-3 text-[11px] font-medium bg-blue-600 text-white rounded-[6px] cursor-pointer hover:bg-blue-700 border-none"
                >
                  Add
                </button>
              </form>
            </div>

            <%!-- Footer --%>
            <div class="flex justify-end px-4 py-[10px] border-t border-gray-200 dark:border-gray-700">
              <button
                type="button"
                phx-click="close"
                phx-target={@myself}
                class="h-[28px] px-[14px] text-[11px] font-medium bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 border border-gray-200 dark:border-gray-600 rounded-[6px] cursor-pointer hover:bg-gray-200 dark:hover:bg-gray-600"
              >
                Close
              </button>
            </div>
          </div>
        </.focus_wrap>
      </div>
    </div>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  # Returns {dot, bg, text} for a given palette hex colour.
  # Falls back to generic light/dark if the hex is not in the palette.
  @spec palette_triplet(String.t()) :: Taniwha.LabelStore.colour_triplet()
  defp palette_triplet(dot) do
    pairs = [
      {"#ec4899", "#fce7f3", "#be185d"},
      {"#6366f1", "#e0e7ff", "#4338ca"},
      {"#a855f7", "#f3e8ff", "#7e22ce"},
      {"#22c55e", "#dcfce7", "#15803d"},
      {"#3b82f6", "#dbeafe", "#1d4ed8"},
      {"#f59e0b", "#fef3c7", "#b45309"}
    ]

    case Enum.find(pairs, fn {d, _, _} -> d == dot end) do
      nil -> {dot, "#f3f4f6", "#374151"}
      triplet -> triplet
    end
  end
end
