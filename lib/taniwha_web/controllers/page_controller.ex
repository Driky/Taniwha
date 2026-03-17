defmodule TaniwhaWeb.PageController do
  use TaniwhaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
