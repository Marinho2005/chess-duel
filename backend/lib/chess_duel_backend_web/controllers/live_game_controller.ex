defmodule ChessDuelBackendWeb.LiveGameController do
  use ChessDuelBackendWeb, :controller

  def index(conn, _params), do: json(conn, %{games: ChessDuelBackend.Games.list_live_human_games()})
end
