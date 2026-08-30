defmodule ChessDuelBackend.GameAnalysis do
  import Ecto.Query, warn: false

  alias ChessDuelBackend.GameAnalysis.{Analysis, Job}
  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackend.Repo

  def request(game_id, user_id) do
    with {:ok, game} <- authorized_finished_game(game_id, user_id),
         {:ok, analysis} <- get_or_create(game) do
      maybe_enqueue(analysis)
      {:ok, analysis, game}
    end
  end

  def get(game_id, user_id) do
    with {:ok, game} <- authorized_finished_game(game_id, user_id),
         %Analysis{} = analysis <- Repo.get_by(Analysis, game_id: game.id) do
      {:ok, analysis, game}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def mark_processing(id) do
    case Repo.get(Analysis, id) |> Repo.preload(:game) do
      nil ->
        {:error, :not_found}

      analysis ->
        analysis |> Analysis.changeset(%{status: "processing", error: nil}) |> Repo.update()
    end
  end

  def complete(analysis, results),
    do:
      analysis
      |> Analysis.changeset(%{status: "completed", results: results, error: nil})
      |> Repo.update()

  def fail(id, reason) do
    case Repo.get(Analysis, id) do
      nil ->
        {:error, :not_found}

      analysis ->
        analysis |> Analysis.changeset(%{status: "failed", error: reason}) |> Repo.update()
    end
  end

  defp authorized_finished_game(id, user_id) do
    case Repo.get(Game, id) do
      nil ->
        {:error, :not_found}

      %Game{status: status} when status != "finished" ->
        {:error, :unfinished}

      %Game{} = game when game.white_player_id == user_id or game.black_player_id == user_id ->
        {:ok, game}

      %Game{} ->
        {:error, :forbidden}
    end
  end

  defp get_or_create(game) do
    case Repo.get_by(Analysis, game_id: game.id) do
      nil ->
        %Analysis{} |> Analysis.changeset(%{game_id: game.id}) |> Repo.insert()

      %Analysis{status: "failed"} = analysis ->
        analysis |> Analysis.changeset(%{status: "pending", error: nil}) |> Repo.update()

      analysis ->
        {:ok, analysis}
    end
  end

  defp maybe_enqueue(%Analysis{status: "pending"} = analysis) do
    %{analysis_id: analysis.id}
    |> Job.new(unique: [period: 300, fields: [:args, :worker]])
    |> Oban.insert()
  end

  defp maybe_enqueue(_analysis), do: :ok
end
