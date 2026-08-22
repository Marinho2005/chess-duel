defmodule ChessDuelBackendWeb.UserController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackendWeb.UserJSON

  def me(conn, _params) do
    json(conn, %{user: UserJSON.data(conn.assigns.current_user)})
  end
end
