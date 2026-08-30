defmodule ChessDuelBackend.GameAnalysis.Job do
  use Oban.Worker, queue: :analysis, max_attempts: 3

  alias ChessDuelBackend.GameAnalysis
  alias ChessDuelBackend.GameAnalysis.Stockfish

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"analysis_id" => id}}) do
    with {:ok, analysis} <- GameAnalysis.mark_processing(id),
         {:ok, results} <- Stockfish.analyze(analysis.game.moves),
         {:ok, _analysis} <- GameAnalysis.complete(analysis, results) do
      :ok
    else
      {:error, reason} ->
        GameAnalysis.fail(id, inspect(reason))
        {:error, reason}
    end
  end
end
