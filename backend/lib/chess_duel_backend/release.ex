defmodule ChessDuelBackend.Release do
  @moduledoc "Migrations via bin/chess_duel_backend eval, sem Mix ou servidores de jogo."
  @app :chess_duel_backend

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
