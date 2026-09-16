defmodule ChessDuelBackendWeb.BroadcastController do
  use ChessDuelBackendWeb, :controller

  def index(conn, _params), do: json(conn, %{games: ChessDuelBackend.Broadcasts.list_live_games()})

  def tournaments(conn, _params),
    do: json(conn, %{tournaments: ChessDuelBackend.Broadcasts.list_live_tournaments()})

  def tournament_games(conn, %{"tournament_id" => tournament_id}),
    do: json(conn, %{games: ChessDuelBackend.Broadcasts.list_tournament_games(tournament_id)})

  def tournament(conn, %{"tournament_id" => id}) do
    respond(conn, ChessDuelBackend.Broadcasts.Archive.tournament(id), :tournament)
  end

  def round_games(conn, %{"round_id" => id}) do
    respond(conn, ChessDuelBackend.Broadcasts.Archive.round_games(id), :games)
  end

  defp respond(conn, {:ok, data}, key), do: json(conn, %{key => data})

  defp respond(conn, {:error, reason}, _key) do
    status =
      case reason do
        :not_found -> 404
        {:http_error, 404} -> 404
        :rate_limited -> 503
        _ -> 502
      end

    conn
    |> put_status(status)
    |> json(%{error: "Não foi possível carregar o broadcast. Tente novamente em instantes."})
  end
end
