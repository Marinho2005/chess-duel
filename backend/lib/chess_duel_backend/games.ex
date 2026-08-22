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
  def get_game_by_game_id(game_id), do: Repo.get_by(Game, game_id: game_id)

  def get_or_create_game(game_id, attrs) do
    case get_game_by_game_id(game_id) do
      nil -> create_game(Map.put(attrs, :game_id, game_id))
      game -> {:ok, game}
    end
  end

  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end
end
