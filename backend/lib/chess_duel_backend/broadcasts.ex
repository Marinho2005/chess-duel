defmodule ChessDuelBackend.Broadcasts do
  @moduledoc "Public boundary for the ephemeral Lichess broadcast snapshot."

  alias ChessDuelBackend.Broadcasts.Cache

  def list_live_games, do: Cache.list_games()
  def list_live_tournaments, do: Cache.list_tournaments()
  def list_tournament_games(tournament_id), do: Cache.list_tournament_games(tournament_id)
  def get_live_game(game_id), do: Cache.get_game(game_id)
  def refresh, do: Cache.refresh()
end
