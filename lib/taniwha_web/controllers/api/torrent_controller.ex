defmodule TaniwhaWeb.API.TorrentController do
  @moduledoc """
  REST endpoints for torrent management.

  Reads state from `Taniwha.State.Store` (ETS) and delegates mutations to
  `Taniwha.Commands` via the configured commands module.
  """

  use TaniwhaWeb, :controller

  alias Taniwha.{State.Store, Validator}

  @commands Application.compile_env(:taniwha, :commands, Taniwha.Commands)

  @doc "Returns all torrents currently in the ETS store."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    torrents = Store.get_all_torrents()
    render(conn, :index, torrents: torrents)
  end

  @doc "Returns a single torrent by hash, or 404 if not found."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"hash" => hash}) do
    case Store.get_torrent(hash) do
      {:ok, torrent} -> render(conn, :show, torrent: torrent)
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not_found"})
    end
  end

  @doc """
  Adds a torrent from a magnet URL or an uploaded `.torrent` file.

  Accepts optional `"label"` and `"directory"` params. When provided they are
  forwarded as post-load commands to rtorrent via `Commands.load_url/2` or
  `Commands.load_raw/2`.

  Returns 201 with `%{"status" => "queued"}` on success, 422 on error or
  when neither a magnet URL nor a file is provided.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"magnet_url" => url} = params) do
    opts = build_load_opts(params)

    case Validator.validate_url(url) do
      :ok -> load_reply(conn, @commands.load_url(url, opts))
      {:error, :invalid_url} -> conn |> put_status(422) |> json(%{error: "invalid_url"})
    end
  end

  def create(conn, %{"torrent" => %Plug.Upload{path: path}} = params) do
    opts = build_load_opts(params)

    case File.read(path) do
      {:ok, binary} -> load_reply(conn, @commands.load_raw(binary, opts))
      {:error, reason} -> conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(422) |> json(%{error: "magnet_url or torrent file required"})
  end

  @doc """
  Removes a torrent from rtorrent.

  Accepts an optional `delete_files=true` query parameter. When present the
  torrent's downloaded files are also deleted from disk via
  `Commands.erase_with_data/1`. Without it only the torrent record is removed.

  Returns 204 on success, 422 on error.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def delete(conn, %{"hash" => hash} = params) do
    delete_files = Map.get(params, "delete_files", "false") == "true"

    result =
      if delete_files do
        @commands.erase_with_data(hash)
      else
        @commands.erase(hash)
      end

    case result do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  @spec load_reply(Plug.Conn.t(), :ok | {:error, term()}) :: Plug.Conn.t()
  defp load_reply(conn, :ok), do: conn |> put_status(201) |> render(:create, status: "queued")

  defp load_reply(conn, {:error, reason}),
    do: conn |> put_status(422) |> json(%{error: inspect(reason)})

  @spec build_load_opts(map()) :: keyword()
  defp build_load_opts(params) do
    []
    |> maybe_add_opt(params, "label", :label)
    |> maybe_add_opt(params, "directory", :directory)
  end

  @spec maybe_add_opt(keyword(), map(), String.t(), atom()) :: keyword()
  defp maybe_add_opt(opts, params, key, atom) do
    case Map.get(params, key) do
      nil -> opts
      val -> Keyword.put(opts, atom, val)
    end
  end
end
