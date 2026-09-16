defmodule ChessDuelBackend.GameAnalysis do
  import Ecto.Query, warn: false

  alias ChessDuelBackend.GameAnalysis.{Analysis, Job}
  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackend.Repo

  def request(game_id, _user_id) do
    with {:ok, game} <- finished_game(game_id),
         {:ok, analysis} <- get_or_create(game) do
      maybe_enqueue(analysis)
      {:ok, analysis, game}
    end
  end

  def get(game_id, _user_id) do
    with {:ok, game} <- finished_game(game_id) do
      # Reading a replay never schedules Stockfish work.
      analysis = Repo.get_by(Analysis, game_id: game.id) || %Analysis{status: "missing"}
      {:ok, analysis, game}
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

  defp finished_game(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      find_finished_game(uuid)
    else
      _ -> {:error, :not_found}
    end
  end

  defp find_finished_game(id) do
    case Repo.get(Game, id) do
      nil ->
        {:error, :not_found}

      %Game{status: status} when status != "finished" ->
        {:error, :unfinished}

      %Game{} = game ->
        {:ok, game}
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
