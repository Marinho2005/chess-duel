defmodule ChessDuelBackendWeb.GuestSessionController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts.Guest

  def create(conn, _params) do
    json(conn, Guest.new())
  end
end
