defmodule ChessDuelBackendWeb.LiveGameController do
  use ChessDuelBackendWeb, :controller

  @categories ~w(bullet blitz blitz_increment rapid)

  def index(conn, params) do
    category = params["category"]

    if is_nil(category) or category in @categories do
      json(conn, %{
        games: ChessDuelBackend.Games.list_live_human_games(category: category, limit: 30)
      })
    else
      conn |> put_status(:bad_request) |> json(%{error: "invalid_category"})
    end
  end
end
