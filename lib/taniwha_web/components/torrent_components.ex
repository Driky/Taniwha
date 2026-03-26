defmodule TaniwhaWeb.TorrentComponents do
  @moduledoc """
  Umbrella for all Taniwha torrent UI components.

  Use this module to bring all component sub-modules into scope at once:

      use TaniwhaWeb.TorrentComponents

  This is equivalent to importing each sub-module individually:

  - `TaniwhaWeb.TorrentComponents.StatusComponents` — `progress_bar/1`, `status_badge/1`, `speed_display/1`, `connection_banner/1`
  - `TaniwhaWeb.TorrentComponents.LayoutComponents` — `topbar/1`, `sidebar/1`
  - `TaniwhaWeb.TorrentComponents.TableComponents` — `action_bar/1`, `table_header/1`, `torrent_row/1`, `torrent_table/1`
  - `TaniwhaWeb.TorrentComponents.DetailComponents` — `detail_panel/1`, `general_tab/1`, `files_tab/1`, `peers_tab/1`, `trackers_tab/1`
  - `TaniwhaWeb.TorrentComponents.Dialogs` — `confirmation_dialog/1`
  """

  defmacro __using__(_opts) do
    quote do
      import TaniwhaWeb.TorrentComponents.StatusComponents
      import TaniwhaWeb.TorrentComponents.LayoutComponents
      import TaniwhaWeb.TorrentComponents.TableComponents
      import TaniwhaWeb.TorrentComponents.DetailComponents
      import TaniwhaWeb.TorrentComponents.Dialogs
    end
  end
end
