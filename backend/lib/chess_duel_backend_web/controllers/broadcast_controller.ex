defmodule ChessDuelBackendWeb.BroadcastController do
  use ChessDuelBackendWeb, :controller

  def index(conn, _params), do: json(conn, %{games: ChessDuelBackend.Broadcasts.list_live_games()})
end
