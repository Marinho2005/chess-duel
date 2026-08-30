defmodule ChessDuelBackendWeb.GameAnalysisController do
  use ChessDuelBackendWeb, :controller
  import Ecto.Query, warn: false

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.GameAnalysis
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
    case GameAnalysis.get(id, conn.assigns.current_user.id) do
      {:ok, analysis, game} -> json(conn, payload(analysis, game, conn.assigns.current_user.id))
      error -> render_error(conn, error)
    end
  end

  defp payload(analysis, game, user_id) do
    players =
      [game.white_player_id, game.black_player_id]
      |> Enum.reject(&is_nil/1)
      |> then(fn ids ->
        Repo.all(
          from user in User,
            where: user.id in ^ids,
            select: {user.id, %{id: user.id, nickname: user.nickname, avatar_url: user.avatar_path}}
        )
      end)
      |> Map.new()

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
        viewer_color: if(game.white_player_id == user_id, do: "white", else: "black"),
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
