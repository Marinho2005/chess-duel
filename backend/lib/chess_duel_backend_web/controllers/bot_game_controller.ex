defmodule ChessDuelBackendWeb.BotGameController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Games.{BotGames, Bots}

  def index(conn, _params), do: json(conn, %{bots: Enum.map(Bots.all(), &Bots.public/1)})

  def create(conn, %{"bot_id" => bot_id, "time_control" => control, "color" => color}) do
    case BotGames.create(conn.assigns.current_user.id, bot_id, control, color) do
      {:ok, game} ->
        conn |> put_status(:created) |> json(game)

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def create(conn, _params),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_params"})
end
