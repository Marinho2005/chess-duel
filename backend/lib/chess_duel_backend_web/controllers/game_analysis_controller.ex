defmodule ChessDuelBackendWeb.GameAnalysisController do
  use ChessDuelBackendWeb, :controller
  import Ecto.Query, warn: false

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.GameAnalysis
  alias ChessDuelBackend.Games.Bots
  alias ChessDuelBackend.Repo

  def create(conn, %{"id" => id}) do
    case GameAnalysis.request(id, conn.assigns.current_user.id) do
      {:ok, analysis, game} ->
        conn
        |> put_status(status_for(analysis.status))
        |> json(payload(analysis, game, conn.assigns.current_user.id))

      error ->
        render_error(conn, error)
    end
  end

  def show(conn, %{"id" => id}) do
    user_id = conn.assigns[:current_user] && conn.assigns.current_user.id
    case GameAnalysis.get(id, user_id) do
      {:ok, analysis, game} -> json(conn, payload(analysis, game, user_id))
      error -> render_error(conn, error)
    end
  end

  defp payload(analysis, game, user_id) do
    players =
      [game.white_player_id, game.black_player_id]
      |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
      |> then(fn ids ->
        Repo.all(
          from user in User,
            where: user.id in ^ids,
            select:
              {user.id,
               %{
                 id: user.id,
                 nickname: user.nickname,
                 avatar_url: user.avatar_path,
                 country_code: user.country_code
               }}
        )
      end)
      |> Map.new()
      |> then(fn players ->
        if game.bot_id do
          bot = Bots.get(game.bot_id)
          Map.put(players, Bots.player_id(game.bot_id), Bots.public(bot))
        else
          players
        end
      end)

    %{
      id: analysis.id,
      status: analysis.status,
      results: analysis.results,
      error: if(analysis.status == "failed", do: "A análise falhou. Tente novamente.", else: nil),
      game: %{
        id: game.id,
        moves: game.moves,
        result: game.result,
        end_reason: game.end_reason,
        viewer_color: if(not is_nil(user_id) and game.black_player_id == user_id, do: "black", else: "white"),
        white_player: Map.get(players, game.white_player_id),
        black_player: Map.get(players, game.black_player_id)
      }
    }
  end

  defp status_for("completed"), do: :ok
  defp status_for(_status), do: :accepted

  defp render_error(conn, {:error, :not_found}),
    do: conn |> put_status(:not_found) |> json(%{error: "Partida ou análise não encontrada."})

  defp render_error(conn, {:error, :forbidden}),
    do: conn |> put_status(:forbidden) |> json(%{error: "Você não participa desta partida."})

  defp render_error(conn, {:error, :unfinished}),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "A partida precisa estar finalizada."})
end
