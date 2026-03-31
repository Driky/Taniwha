defmodule TaniwhaWeb.TorrentComponents.Dialogs do
  @moduledoc """
  Modal dialog components for destructive-action confirmation.
  """

  use TaniwhaWeb, :html

  # ---------------------------------------------------------------------------
  # confirmation_dialog/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a confirmation dialog overlay.

  Displayed when `confirm_action` is non-nil. Pattern-matches on the action
  tuple to render the appropriate variant.

  ## Variants

    * `nil` — renders nothing
    * `{:erase, hash}` — single-torrent remove (files kept)
    * `{:bulk_erase, [hash]}` — bulk remove (files kept)
    * `{:erase_with_data, hash, base_path}` — single-torrent remove + delete files
    * `{:bulk_erase_with_data, [hash], [path]}` — bulk remove + delete files

  ## Examples

      <.confirmation_dialog confirm_action={@confirm_action} torrent_name="Foo.torrent" />
  """
  attr :confirm_action, :any,
    default: nil,
    doc:
      "nil | {:erase, hash} | {:bulk_erase, [hash]} | {:erase_with_data, hash, path} | {:bulk_erase_with_data, [hash], [path]}"

  attr :torrent_name, :string, default: nil, doc: "display name shown in the message"

  def confirmation_dialog(%{confirm_action: nil} = assigns) do
    ~H"""
    """
  end

  def confirmation_dialog(%{confirm_action: {:erase_with_data, _hash, _base_path}} = assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 dark:bg-black/55"
      phx-click="cancel_confirm"
    >
      <.focus_wrap
        id="confirmation-dialog-wrap"
        phx-key="Escape"
        phx-window-keydown="cancel_confirm"
        class="w-full max-w-[500px] mx-4"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="confirm-dialog-title"
          class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-[0_25px_80px_rgba(0,0,0,0.2)] dark:shadow-[0_25px_80px_rgba(0,0,0,0.6)]"
          phx-click-away="cancel_confirm"
        >
          <div class="px-5 pt-4 pb-[14px] border-b border-gray-200 dark:border-gray-700">
            <h2
              id="confirm-dialog-title"
              class="text-[14px] font-semibold text-gray-900 dark:text-gray-50 flex items-center gap-2"
            >
              <svg
                class="size-4 text-amber-500 shrink-0"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
                />
              </svg>
              Remove torrent and delete files?
            </h2>
          </div>
          <div class="px-5 py-4 text-[12px] text-gray-600 dark:text-gray-300 space-y-3">
            <p>
              The torrent will be removed from rtorrent and the following files will be permanently deleted from disk:
            </p>
            <pre
              :if={elem(@confirm_action, 2)}
              class="bg-gray-100 dark:bg-gray-900 rounded px-3 py-2 text-[11px] font-mono break-all whitespace-pre-wrap text-gray-800 dark:text-gray-200"
            >{elem(@confirm_action, 2)}</pre>
            <p class="font-semibold text-red-700 dark:text-red-400">
              This cannot be undone.
            </p>
          </div>
          <div class="px-5 py-3 flex justify-end gap-2 border-t border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900 rounded-b-xl">
            <button
              type="button"
              phx-click="cancel_confirm"
              class="h-8 px-4 text-[12px] rounded-[7px] text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
              aria-label="Cancel removal"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="confirm_action"
              class="h-8 px-4 text-[12px] font-medium rounded-[7px] bg-red-600 hover:bg-red-700 text-white cursor-pointer"
              aria-label="Confirm delete files and remove torrent"
            >
              Delete files
            </button>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  def confirmation_dialog(%{confirm_action: {:bulk_erase_with_data, _hashes, _paths}} = assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 dark:bg-black/55"
      phx-click="cancel_confirm"
    >
      <.focus_wrap
        id="confirmation-dialog-wrap"
        phx-key="Escape"
        phx-window-keydown="cancel_confirm"
        class="w-full max-w-[500px] mx-4"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="confirm-dialog-title"
          class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-[0_25px_80px_rgba(0,0,0,0.2)] dark:shadow-[0_25px_80px_rgba(0,0,0,0.6)]"
          phx-click-away="cancel_confirm"
        >
          <div class="px-5 pt-4 pb-[14px] border-b border-gray-200 dark:border-gray-700">
            <h2
              id="confirm-dialog-title"
              class="text-[14px] font-semibold text-gray-900 dark:text-gray-50 flex items-center gap-2"
            >
              <svg
                class="size-4 text-amber-500 shrink-0"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
                />
              </svg>
              Remove {length(elem(@confirm_action, 1))} torrents and delete their files?
            </h2>
          </div>
          <div class="px-5 py-4 text-[12px] text-gray-600 dark:text-gray-300 space-y-3">
            <p>
              The following paths will be permanently deleted from disk:
            </p>
            <ul class="space-y-1">
              <li
                :for={path <- elem(@confirm_action, 2)}
                :if={path}
                class="bg-gray-100 dark:bg-gray-900 rounded px-3 py-1 text-[11px] font-mono break-all text-gray-800 dark:text-gray-200"
              >
                {path}
              </li>
            </ul>
            <p class="font-semibold text-red-700 dark:text-red-400">
              This cannot be undone.
            </p>
          </div>
          <div class="px-5 py-3 flex justify-end gap-2 border-t border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900 rounded-b-xl">
            <button
              type="button"
              phx-click="cancel_confirm"
              class="h-8 px-4 text-[12px] rounded-[7px] text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
              aria-label="Cancel removal"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="confirm_action"
              class="h-8 px-4 text-[12px] font-medium rounded-[7px] bg-red-600 hover:bg-red-700 text-white cursor-pointer"
              aria-label="Confirm delete files and remove torrents"
            >
              Delete files
            </button>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end

  def confirmation_dialog(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 dark:bg-black/55"
      phx-click="cancel_confirm"
    >
      <.focus_wrap
        id="confirmation-dialog-wrap"
        phx-key="Escape"
        phx-window-keydown="cancel_confirm"
        class="w-full max-w-[500px] mx-4"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="confirm-dialog-title"
          class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-[0_25px_80px_rgba(0,0,0,0.2)] dark:shadow-[0_25px_80px_rgba(0,0,0,0.6)]"
          phx-click-away="cancel_confirm"
        >
          <div class="px-5 pt-4 pb-[14px] border-b border-gray-200 dark:border-gray-700">
            <h2
              id="confirm-dialog-title"
              class="text-[14px] font-semibold text-gray-900 dark:text-gray-50"
            >
              Remove torrent?
            </h2>
          </div>
          <div class="px-5 py-4 text-[12px] text-gray-600 dark:text-gray-300">
            <p :if={@torrent_name}>
              <span class="font-medium text-gray-900 dark:text-gray-50">{@torrent_name}</span>
              {" "}will be removed from rtorrent. Downloaded files will not be deleted.
            </p>
            <p :if={is_tuple(@confirm_action) and elem(@confirm_action, 0) == :bulk_erase}>
              {length(elem(@confirm_action, 1))} torrents will be removed from rtorrent.
              Downloaded files will not be deleted.
            </p>
          </div>
          <div class="px-5 py-3 flex justify-end gap-2 border-t border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900 rounded-b-xl">
            <button
              type="button"
              phx-click="cancel_confirm"
              class="h-8 px-4 text-[12px] rounded-[7px] text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-600 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
              aria-label="Cancel removal"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="confirm_action"
              class="h-8 px-4 text-[12px] font-medium rounded-[7px] bg-red-600 hover:bg-red-700 text-white cursor-pointer"
              aria-label="Confirm removal"
            >
              Remove
            </button>
          </div>
        </div>
      </.focus_wrap>
    </div>
    """
  end
end
