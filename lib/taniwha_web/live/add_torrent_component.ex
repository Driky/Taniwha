defmodule TaniwhaWeb.AddTorrentComponent do
  @moduledoc """
  LiveComponent for the "Add Torrent" modal overlay.

  Rendered inside `DashboardLive` when `@show_add_modal` is true. Supports two
  modes: magnet/URL submission and .torrent file upload. The parent LiveView owns
  the upload (via `allow_upload/3` in `DashboardLive.mount/3`) and handles the
  `submit_file`, `validate`, and `cancel_upload` events directly.
  """

  use TaniwhaWeb, :live_component

  import TaniwhaWeb.FormatHelpers, only: [format_add_error: 1]
  import TaniwhaWeb.FolderPicker, only: [folder_picker: 1]

  alias Taniwha.FileSystem

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  @impl true
  def mount(socket) do
    base = FileSystem.default_download_dir()

    {:ok,
     socket
     |> assign(:active_tab, :url)
     |> assign(:url, "")
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:selected_label, nil)
     |> assign(:label_groups, [])
     |> assign(:download_dir, base)
     |> assign(:folder_picker_open, false)
     |> assign(:folder_picker_root, base)
     |> assign(:folder_picker_selected, base)
     |> assign(:folder_picker_expanded, MapSet.new())
     |> assign(:folder_picker_children, %{})
     |> assign(:folder_picker_loading, MapSet.new())}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => "url"}, socket) do
    {:noreply, assign(socket, active_tab: :url, error: nil)}
  end

  def handle_event("switch_tab", %{"tab" => "file"}, socket) do
    {:noreply, assign(socket, active_tab: :file, error: nil)}
  end

  def handle_event("select_label", %{"label" => label}, socket) do
    selected =
      if socket.assigns.selected_label == label, do: nil, else: label

    {:noreply, assign(socket, :selected_label, selected)}
  end

  def handle_event("open_folder_picker", _params, socket) do
    base = FileSystem.default_download_dir()

    if base do
      {:ok, entries} = FileSystem.list_directories(base, base)
      current = socket.assigns.download_dir || base

      {:noreply,
       socket
       |> assign(:folder_picker_open, true)
       |> assign(:folder_picker_root, base)
       |> assign(:folder_picker_selected, current)
       |> assign(:folder_picker_expanded, MapSet.new([base]))
       |> assign(:folder_picker_children, %{base => entries})
       |> assign(:folder_picker_loading, MapSet.new())}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_folder", %{"path" => path}, socket) do
    expanded = socket.assigns.folder_picker_expanded
    base = socket.assigns.folder_picker_root

    if MapSet.member?(expanded, path) do
      {:noreply, assign(socket, :folder_picker_expanded, MapSet.delete(expanded, path))}
    else
      loading = MapSet.put(socket.assigns.folder_picker_loading, path)
      socket = assign(socket, :folder_picker_loading, loading)

      case FileSystem.list_directories(path, base) do
        {:ok, entries} ->
          {:noreply,
           socket
           |> assign(
             :folder_picker_children,
             Map.put(socket.assigns.folder_picker_children, path, entries)
           )
           |> assign(:folder_picker_expanded, MapSet.put(expanded, path))
           |> assign(
             :folder_picker_loading,
             MapSet.delete(socket.assigns.folder_picker_loading, path)
           )}

        {:error, _} ->
          {:noreply, assign(socket, :folder_picker_loading, MapSet.delete(loading, path))}
      end
    end
  end

  def handle_event("select_folder_node", %{"path" => path}, socket) do
    {:noreply, assign(socket, :folder_picker_selected, path)}
  end

  def handle_event("confirm_folder", _params, socket) do
    {:noreply,
     socket
     |> assign(:download_dir, socket.assigns.folder_picker_selected)
     |> assign(:folder_picker_open, false)}
  end

  def handle_event("close_folder_picker", _params, socket) do
    {:noreply, assign(socket, :folder_picker_open, false)}
  end

  def handle_event("submit_url", %{"url" => url}, socket) do
    url = String.trim(url)

    case Taniwha.Validator.validate_url(url) do
      {:error, :invalid_url} ->
        {:noreply, assign(socket, :error, "Please enter a valid magnet link or HTTP/HTTPS URL.")}

      :ok ->
        socket = assign(socket, :loading, true)

        opts =
          socket.assigns.selected_label
          |> label_opt()
          |> maybe_add_directory(socket.assigns.download_dir)

        case @commands.load_url(url, opts) do
          :ok ->
            send(self(), {:add_torrent_success})
            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:loading, false)
             |> assign(:error, format_add_error(reason))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-50">
      <%!-- Backdrop: sibling to modal wrapper so modal clicks don't bubble to it --%>
      <div
        class="absolute inset-0 bg-black/30 dark:bg-black/55"
        phx-click="hide_add_modal"
        phx-target={false}
        aria-hidden="true"
      />
      <%!-- Modal wrapper: pointer-events-none so dark-area clicks pass through to backdrop --%>
      <div class="absolute inset-0 flex items-center justify-center pointer-events-none">
        <.focus_wrap
          id={"#{@id}-wrap"}
          phx-key="Escape"
          phx-window-keydown="keydown"
          phx-target={false}
          class="w-full max-w-[500px] mx-4 pointer-events-auto"
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby={"#{@id}-title"}
            class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-[0_25px_80px_rgba(0,0,0,0.2)] dark:shadow-[0_25px_80px_rgba(0,0,0,0.6)]"
          >
            <%!-- Header --%>
            <div class="flex items-center justify-between px-5 pt-4 pb-[14px] border-b border-gray-200 dark:border-gray-700">
              <h2
                id={"#{@id}-title"}
                class="text-[14px] font-semibold text-gray-900 dark:text-gray-50"
              >
                Add Torrent
              </h2>
              <button
                type="button"
                phx-click="hide_add_modal"
                phx-target={false}
                aria-label="Close dialog"
                class="size-6 flex items-center justify-center rounded-md text-gray-400 hover:text-gray-600 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer"
              >
                <.icon name="hero-x-mark-mini" class="size-4" />
              </button>
            </div>

            <%!-- Tab bar --%>
            <div
              class="flex border-b border-gray-200 dark:border-gray-700 px-5"
              role="tablist"
              aria-label="Add torrent mode"
            >
              <button
                type="button"
                role="tab"
                phx-click="switch_tab"
                phx-value-tab="url"
                phx-target={@myself}
                aria-selected={to_string(@active_tab == :url)}
                aria-controls={"#{@id}-url-panel"}
                class={[
                  "h-10 text-[12px] mr-5 border-b-2 transition-colors",
                  @active_tab == :url &&
                    "text-blue-600 dark:text-blue-400 border-blue-500",
                  @active_tab != :url &&
                    "text-gray-500 border-transparent hover:text-gray-700 dark:hover:text-gray-300"
                ]}
              >
                Magnet / URL
              </button>
              <button
                type="button"
                role="tab"
                phx-click="switch_tab"
                phx-value-tab="file"
                phx-target={@myself}
                aria-selected={to_string(@active_tab == :file)}
                aria-controls={"#{@id}-file-panel"}
                class={[
                  "h-10 text-[12px] border-b-2 transition-colors",
                  @active_tab == :file &&
                    "text-blue-600 dark:text-blue-400 border-blue-500",
                  @active_tab != :file &&
                    "text-gray-500 border-transparent hover:text-gray-700 dark:hover:text-gray-300"
                ]}
              >
                File upload
              </button>
            </div>

            <%!-- Error banner --%>
            <div
              :if={@error}
              role="alert"
              class="mx-5 mt-4 px-3 py-2 text-[11px] text-red-700 dark:text-red-400 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-700/50 rounded-lg"
            >
              {@error}
            </div>

            <%!-- URL panel --%>
            <div
              :if={@active_tab == :url}
              id={"#{@id}-url-panel"}
              role="tabpanel"
              aria-labelledby={"#{@id}-tab-url"}
              class="p-5"
            >
              <form phx-submit="submit_url" phx-target={@myself} id={"#{@id}-url-form"}>
                <label for={"#{@id}-url-input"} class="block text-[11px] text-gray-500 mb-[6px]">
                  Magnet link or .torrent URL
                </label>
                <input
                  id={"#{@id}-url-input"}
                  type="text"
                  name="url"
                  value={@url}
                  placeholder="magnet:?xt=urn:btih:…"
                  autocomplete="off"
                  spellcheck="false"
                  class="w-full px-3 py-2 text-[12px] font-mono border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-900 text-gray-700 dark:text-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                <p class="mt-[6px] text-[10px] text-gray-400">
                  Paste a magnet link or direct link to a .torrent file.
                </p>
                <%!-- Hidden submit so Enter key works --%>
                <button type="submit" class="sr-only" aria-label="Submit magnet URL" />
              </form>
              <%!-- Label selector --%>
              <div :if={@label_groups != []} class="mt-3">
                <p class="text-[11px] text-gray-500 dark:text-gray-400 mb-[6px]">Label</p>
                <div class="flex flex-wrap gap-[6px]" role="group" aria-label="Select label">
                  <%= for {label, _count} <- @label_groups do %>
                    <% {dot, bg, text} = Taniwha.LabelStore.auto_assign(label) %>
                    <button
                      type="button"
                      phx-click="select_label"
                      phx-target={@myself}
                      phx-value-label={label}
                      aria-pressed={to_string(@selected_label == label)}
                      class={[
                        "inline-flex items-center gap-[5px] h-[22px] px-[8px] text-[11px] rounded-full border cursor-pointer transition-colors",
                        @selected_label == label &&
                          "border-transparent",
                        @selected_label != label &&
                          "border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:border-gray-300"
                      ]}
                      style={
                        if @selected_label == label,
                          do: "background-color: #{bg}; color: #{text};",
                          else: ""
                      }
                    >
                      <span
                        class="size-[7px] rounded-full shrink-0"
                        style={"background-color: #{dot}"}
                        aria-hidden="true"
                      />{label}
                    </button>
                  <% end %>
                </div>
              </div>
              <%!-- Download directory picker --%>
              <div :if={@folder_picker_root} class="mt-3">
                <label
                  for={"#{@id}-url-dir-input"}
                  class="block text-[11px] text-gray-500 dark:text-gray-400 mb-[6px]"
                >
                  Download directory
                </label>
                <div class="flex gap-[6px] items-center">
                  <input
                    id={"#{@id}-url-dir-input"}
                    type="text"
                    readonly
                    value={@download_dir || ""}
                    class="flex-1 h-[30px] px-[10px] text-[11px] font-mono border border-gray-300 dark:border-gray-600 rounded-lg bg-gray-50 dark:bg-gray-900 text-gray-700 dark:text-gray-300 focus:outline-none cursor-default"
                  />
                  <button
                    type="button"
                    phx-click="open_folder_picker"
                    phx-target={@myself}
                    class="h-[30px] px-[10px] text-[11px] rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
                  >
                    Browse
                  </button>
                </div>
              </div>
            </div>

            <%!-- File upload panel --%>
            <div
              :if={@active_tab == :file}
              id={"#{@id}-file-panel"}
              role="tabpanel"
              aria-labelledby={"#{@id}-tab-file"}
              class="p-5"
            >
              <%!-- Download directory picker --%>
              <div :if={@folder_picker_root} class="mb-3">
                <label
                  for={"#{@id}-file-dir-input"}
                  class="block text-[11px] text-gray-500 dark:text-gray-400 mb-[6px]"
                >
                  Download directory
                </label>
                <div class="flex gap-[6px] items-center">
                  <input
                    id={"#{@id}-file-dir-input"}
                    type="text"
                    readonly
                    value={@download_dir || ""}
                    class="flex-1 h-[30px] px-[10px] text-[11px] font-mono border border-gray-300 dark:border-gray-600 rounded-lg bg-gray-50 dark:bg-gray-900 text-gray-700 dark:text-gray-300 focus:outline-none cursor-default"
                  />
                  <button
                    type="button"
                    phx-click="open_folder_picker"
                    phx-target={@myself}
                    class="h-[30px] px-[10px] text-[11px] rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
                  >
                    Browse
                  </button>
                </div>
              </div>
              <form
                phx-submit="submit_file"
                phx-change="validate"
                id={"#{@id}-file-form"}
                phx-drop-target={@file_uploads.torrent_file.ref}
                class="flex flex-col items-center border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-[10px] text-center"
              >
                <input type="hidden" name="download_dir" value={@download_dir || ""} />
                <label
                  for={@file_uploads.torrent_file.ref}
                  class="flex flex-col items-center w-full px-5 py-8 cursor-pointer"
                >
                  <.icon name="hero-arrow-up-tray" class="size-8 text-gray-400 mb-3" />
                  <p class="text-[12px] text-gray-500 mb-1">
                    Drag and drop or <span class="text-blue-500">click to browse</span>
                  </p>
                  <.live_file_input upload={@file_uploads.torrent_file} class="sr-only" />
                </label>
                <%= for entry <- @file_uploads.torrent_file.entries do %>
                  <div class="mt-2 text-[11px] text-gray-600 dark:text-gray-400 flex items-center gap-2">
                    <span>{entry.client_name}</span>
                    <button
                      type="button"
                      phx-click="cancel_upload"
                      phx-value-ref={entry.ref}
                      aria-label={"Cancel #{entry.client_name}"}
                      class="text-gray-400 hover:text-gray-600 cursor-pointer"
                    >
                      <.icon name="hero-x-mark-mini" class="size-3" />
                    </button>
                  </div>
                  <%= for err <- upload_errors(@file_uploads.torrent_file, entry) do %>
                    <p role="alert" class="text-[11px] text-red-600 mt-1">
                      {upload_error_to_string(err)}
                    </p>
                  <% end %>
                <% end %>
                <button type="submit" class="sr-only" aria-label="Submit file upload" />
              </form>
            </div>

            <%!-- Footer --%>
            <div class="flex justify-end gap-2 px-5 py-3 border-t border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900 rounded-b-xl">
              <button
                type="button"
                phx-click="hide_add_modal"
                phx-target={false}
                aria-label="Cancel adding torrent"
                class="h-8 px-4 text-[12px] rounded-[7px] text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
              >
                Cancel
              </button>
              <button
                :if={@active_tab == :url}
                type="button"
                phx-click={JS.dispatch("submit", to: "##{@id}-url-form")}
                disabled={@loading}
                aria-label="Add torrent from URL"
                class={[
                  "h-8 px-4 text-[12px] font-medium rounded-[7px] bg-blue-600 text-white",
                  @loading && "opacity-50 cursor-not-allowed",
                  !@loading && "hover:bg-blue-700 cursor-pointer"
                ]}
              >
                <%= if @loading do %>
                  <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                <% else %>
                  Add
                <% end %>
              </button>
              <button
                :if={@active_tab == :file}
                type="button"
                phx-click={JS.dispatch("submit", to: "##{@id}-file-form")}
                disabled={@loading or Enum.empty?(@file_uploads.torrent_file.entries)}
                aria-label="Add torrent from file"
                class={[
                  "h-8 px-4 text-[12px] font-medium rounded-[7px] bg-blue-600 text-white",
                  (@loading or Enum.empty?(@file_uploads.torrent_file.entries)) &&
                    "opacity-50 cursor-not-allowed",
                  !@loading && !Enum.empty?(@file_uploads.torrent_file.entries) &&
                    "hover:bg-blue-700 cursor-pointer"
                ]}
              >
                Add
              </button>
            </div>
          </div>
        </.focus_wrap>
      </div>
      <%!-- Folder picker overlay --%>
      <.folder_picker
        :if={@folder_picker_open}
        id={"#{@id}-folder-picker"}
        root={@folder_picker_root}
        selected={@folder_picker_selected}
        expanded={@folder_picker_expanded}
        children={@folder_picker_children}
        loading={@folder_picker_loading}
        myself={@myself}
      />
    </div>
    """
  end

  @spec label_opt(String.t() | nil) :: keyword()
  defp label_opt(nil), do: []
  defp label_opt(label), do: [label: label]

  @spec maybe_add_directory(keyword(), String.t() | nil) :: keyword()
  defp maybe_add_directory(opts, dir) do
    default = FileSystem.default_download_dir()

    if is_nil(dir) or dir == "" or dir == default do
      opts
    else
      Keyword.put(opts, :directory, dir)
    end
  end

  @spec upload_error_to_string(atom()) :: String.t()
  defp upload_error_to_string(:too_large), do: "File is too large (max 10 MB)."
  defp upload_error_to_string(:not_accepted), do: "Only .torrent files are accepted."
  defp upload_error_to_string(:too_many_files), do: "Only one file at a time."
  defp upload_error_to_string(_), do: "Upload error. Please try again."
end
