defmodule ChessDuelBackendWeb.BroadcastController do
  use ChessDuelBackendWeb, :controller

  def index(conn, _params), do: json(conn, %{games: ChessDuelBackend.Broadcasts.list_live_games()})

  def tournaments(conn, _params),
    do: json(conn, %{tournaments: ChessDuelBackend.Broadcasts.list_live_tournaments()})

  def tournament_games(conn, %{"tournament_id" => tournament_id}),
    do: json(conn, %{games: ChessDuelBackend.Broadcasts.list_tournament_games(tournament_id)})
end
