defmodule ChessDuelBackend.Games do
  @moduledoc """
  Contexto responsavel pela persistencia das partidas.
  """

  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackend.Repo

  def create_game(attrs \\ %{}) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def get_game!(id), do: Repo.get!(Game, id)

  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end
end
