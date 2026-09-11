defmodule Mix.Tasks.Puzzles.Import do
  use Mix.Task

  @shortdoc "Importa um subconjunto distribuído do CSV de puzzles do Lichess"

  @impl true
  def run(args) do
    {opts, paths, invalid} =
      OptionParser.parse(args,
        strict: [limit: :integer, minimum_popularity: :integer],
        aliases: [l: :limit, p: :minimum_popularity]
      )

    if invalid != [] or length(paths) > 1 do
      Mix.raise("uso: mix puzzles.import [caminho.csv] [--limit 50000] [--minimum-popularity 80]")
    end

    path = List.first(paths) || "priv/repo/lichess_db_puzzle.csv"
    unless File.regular?(path), do: Mix.raise("arquivo não encontrado: #{path}")

    Mix.Task.run("app.start")
    {:ok, result} = ChessDuelBackend.Puzzles.Importer.import(path, opts)

    Mix.shell().info(
      "Importação concluída: #{result.imported} puzzles; #{result.skipped} linhas ignoradas."
    )
  end
end
