defmodule ChessDuelBackend.Broadcasts do
  @moduledoc "Public boundary for the ephemeral Lichess broadcast snapshot."

  alias ChessDuelBackend.Broadcasts.Cache

  def list_live_games, do: Cache.list_games()
  def get_live_game(game_id), do: Cache.get_game(game_id)
  def refresh, do: Cache.refresh()
end
