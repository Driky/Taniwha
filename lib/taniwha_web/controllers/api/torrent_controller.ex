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

  Returns 201 with `%{"status" => "queued"}` on success, 422 on error or
  when neither a magnet URL nor a file is provided.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"magnet_url" => url}) do
    case Validator.validate_url(url) do
      :ok -> load_reply(conn, @commands.load_url(url))
      {:error, :invalid_url} -> conn |> put_status(422) |> json(%{error: "invalid_url"})
    end
  end

  def create(conn, %{"torrent" => %Plug.Upload{path: path}}) do
    case File.read(path) do
      {:ok, binary} -> load_reply(conn, @commands.load_raw(binary))
      {:error, reason} -> conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn |> put_status(422) |> json(%{error: "magnet_url or torrent file required"})
  end

  @spec load_reply(Plug.Conn.t(), :ok | {:error, term()}) :: Plug.Conn.t()
  defp load_reply(conn, :ok), do: conn |> put_status(201) |> render(:create, status: "queued")

  defp load_reply(conn, {:error, reason}),
    do: conn |> put_status(422) |> json(%{error: inspect(reason)})
end
