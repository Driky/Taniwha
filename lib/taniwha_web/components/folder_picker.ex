defmodule TaniwhaWeb.FolderPicker do
  @moduledoc """
  Pure function component rendering a folder picker overlay.

  All state is provided by the parent LiveComponent (`AddTorrentComponent`).
  Events are sent back to the parent via `myself`.

  ## Usage

      <.folder_picker
        id="my-picker"
        root="/downloads"
        selected="/downloads/movies"
        expanded={MapSet.new(["/downloads"])}
        children={%{"/downloads" => [%{name: "movies", path: "/downloads/movies", has_children: false}]}}
        loading={MapSet.new()}
        myself={@myself}
      />
  """

  use TaniwhaWeb, :html

  attr :id, :string, required: true
  attr :root, :string, default: nil
  attr :selected, :string, default: nil
  # MapSet of expanded paths
  attr :expanded, :any, default: nil
  # %{path => [%{name, path, has_children}]}
  attr :children, :map, default: %{}
  # MapSet of paths currently loading
  attr :loading, :any, default: nil
  # LiveComponent target for event routing
  attr :myself, :any, required: true

  @doc """
  Renders the folder picker overlay dialog.
  """
  @spec folder_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def folder_picker(assigns) do
    assigns =
      assigns
      |> assign_new(:expanded, fn -> MapSet.new() end)
      |> assign_new(:loading, fn -> MapSet.new() end)

    ~H"""
    <div class="absolute inset-0 z-10 flex items-center justify-center">
      <%!-- Secondary backdrop — clicking closes the picker --%>
      <div
        class="absolute inset-0 bg-black/30"
        phx-click="close_folder_picker"
        phx-target={@myself}
        aria-hidden="true"
      />
      <.focus_wrap
        id={"#{@id}-wrap"}
        phx-key="Escape"
        phx-window-keydown="close_folder_picker"
        phx-target={@myself}
        class="relative z-10"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Select folder"
          aria-labelledby={"#{@id}-title"}
          class="bg-white dark:bg-gray-800 rounded-xl w-[380px] shadow-[0_20px_60px_rgba(0,0,0,0.2)] dark:shadow-[0_20px_60px_rgba(0,0,0,0.5)]"
        >
          <%!-- Header --%>
          <div class="flex items-center justify-between px-4 pt-4 pb-3 border-b border-gray-200 dark:border-gray-700">
            <h2
              id={"#{@id}-title"}
              class="text-[13px] font-semibold text-gray-900 dark:text-gray-50"
            >
              Select folder
            </h2>
            <button
              type="button"
              phx-click="close_folder_picker"
              phx-target={@myself}
              aria-label="Close folder picker"
              class="size-6 flex items-center justify-center rounded-md text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer"
            >
              <.icon name="hero-x-mark-mini" class="size-4" />
            </button>
          </div>
          <%!-- Tree --%>
          <div class="px-2 py-2 max-h-[280px] overflow-y-auto">
            <ul role="tree" aria-label={@root}>
              <%= for item <- flatten_tree(@root, @children, @expanded, @loading) do %>
                <%= case item do %>
                  <% {path, depth, name, has_children, is_expanded, _is_loading, is_root} -> %>
                    <li
                      role="treeitem"
                      aria-selected={to_string(@selected == path)}
                      aria-expanded={if has_children, do: to_string(is_expanded), else: nil}
                    >
                      <div
                        class={[
                          "flex items-center gap-1 h-[26px] rounded-md text-[11px] cursor-pointer select-none",
                          @selected == path && !is_root &&
                            "bg-blue-50 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300",
                          (@selected != path || is_root) &&
                            "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"
                        ]}
                        style={"padding-left: #{12 + depth * 16}px; padding-right: 8px;"}
                        phx-click={if !is_root, do: "select_folder_node"}
                        phx-value-path={if !is_root, do: path}
                        phx-target={if !is_root, do: @myself}
                      >
                        <%!-- Chevron or spacer --%>
                        <%= if has_children do %>
                          <button
                            type="button"
                            phx-click="toggle_folder"
                            phx-value-path={path}
                            phx-target={@myself}
                            class="shrink-0 text-gray-400 hover:text-gray-600 cursor-pointer"
                            aria-label={
                              if is_expanded, do: "Collapse #{name}", else: "Expand #{name}"
                            }
                          >
                            <%= if is_expanded do %>
                              <.icon name="hero-chevron-down-mini" class="size-3" />
                            <% else %>
                              <.icon name="hero-chevron-right-mini" class="size-3" />
                            <% end %>
                          </button>
                        <% else %>
                          <span class="size-3 shrink-0" aria-hidden="true" />
                        <% end %>
                        <%!-- Folder icon --%>
                        <span
                          class={[
                            "shrink-0",
                            @selected == path && !is_root && "text-blue-500",
                            (@selected != path || is_root) && "text-amber-400"
                          ]}
                          aria-hidden="true"
                        >
                          <.icon name="hero-folder-mini" class="size-3.5" />
                        </span>
                        <%!-- Name --%>
                        <span class={["truncate", is_root && "text-gray-500 dark:text-gray-400"]}>
                          {name}
                        </span>
                      </div>
                    </li>
                  <% {:loading_row, depth} -> %>
                    <li
                      role="treeitem"
                      aria-label="Loading..."
                      class="flex items-center gap-2 h-[26px] text-[11px] text-gray-400"
                      style={"padding-left: #{12 + depth * 16}px;"}
                    >
                      <.icon name="hero-arrow-path-mini" class="size-3 animate-spin" />
                      <span>Loading…</span>
                    </li>
                <% end %>
              <% end %>
            </ul>
          </div>
          <%!-- Current path display --%>
          <div class="px-4 py-2 border-t border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900/50">
            <p class="text-[10px] font-mono text-gray-500 dark:text-gray-400 truncate">
              {@selected || @root}
            </p>
          </div>
          <%!-- Footer --%>
          <div class="flex justify-end gap-2 px-4 py-3 border-t border-gray-100 dark:border-gray-700">
            <button
              type="button"
              phx-click="close_folder_picker"
              phx-target={@myself}
              class="h-8 px-4 text-[12px] rounded-[7px] text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="confirm_folder"
              phx-target={@myself}
              class="h-8 px-4 text-[12px] font-medium rounded-[7px] bg-blue-600 text-white hover:bg-blue-700 cursor-pointer"
            >
              Select
            </button>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Produces a flat list of tree rows for rendering.
  #
  # Each row is one of:
  #   {path, depth, name, has_children?, is_expanded?, is_loading?, is_root?}
  #   {:loading_row, depth}
  @spec flatten_tree(String.t() | nil, map(), MapSet.t(), MapSet.t()) :: list()
  defp flatten_tree(nil, _children_map, _expanded, _loading), do: []

  defp flatten_tree(root, children_map, expanded, loading) do
    root_entries = Map.get(children_map, root, [])
    root_has_children = not Enum.empty?(root_entries)
    is_expanded = MapSet.member?(expanded, root)
    is_loading = MapSet.member?(loading, root)

    root_row = {root, 0, Path.basename(root), root_has_children, is_expanded, is_loading, true}

    cond do
      is_loading ->
        [root_row, {:loading_row, 1}]

      is_expanded ->
        child_rows =
          Enum.flat_map(root_entries, fn entry ->
            flatten_node(entry, children_map, expanded, loading, 1)
          end)

        [root_row | child_rows]

      true ->
        [root_row]
    end
  end

  @spec flatten_node(map(), map(), MapSet.t(), MapSet.t(), non_neg_integer()) :: list()
  defp flatten_node(entry, children_map, expanded, loading, depth) do
    path = entry.path
    has_children = entry.has_children or Map.has_key?(children_map, path)
    is_expanded = MapSet.member?(expanded, path)
    is_loading = MapSet.member?(loading, path)

    row = {path, depth, entry.name, has_children, is_expanded, is_loading, false}

    cond do
      is_loading ->
        [row, {:loading_row, depth + 1}]

      is_expanded ->
        children = Map.get(children_map, path, [])

        child_rows =
          Enum.flat_map(children, fn child ->
            flatten_node(child, children_map, expanded, loading, depth + 1)
          end)

        [row | child_rows]

      true ->
        [row]
    end
  end
end
