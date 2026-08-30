defmodule ChessDuelBackend.Games.BotMoveTask do
  alias ChessDuelBackend.GameAnalysis.Stockfish
  alias ChessDuelBackend.Games.GameServer

  require Logger

  def run(game_id, fen, token, bot) do
    with {:ok, uci} <- Stockfish.best_move(fen, bot.stockfish),
         <<from::binary-size(2), to::binary-size(2), promotion::binary>> <- uci,
         {:ok, state} <-
           GameServer.apply_bot_move(game_id, fen, token, from, to, promotion_or_nil(promotion)) do
      ChessDuelBackendWeb.Endpoint.broadcast("game:#{game_id}", "move_made", %{
        from: from,
        to: to,
        player: "bot:#{bot.id}",
        promotion: promotion_or_nil(promotion),
        captured: List.last(state.moves).captured,
        san: List.last(state.moves).san,
        new_fen: state.fen,
        current_turn: state.current_turn,
        is_check: state.is_check,
        is_checkmate: state.is_checkmate,
        is_stalemate: state.is_stalemate,
        is_draw: state.is_draw,
        white_time_remaining_ms: state.white_time_remaining_ms,
        black_time_remaining_ms: state.black_time_remaining_ms
      })

      if state.status == "finished" do
        ChessDuelBackendWeb.Endpoint.broadcast("game:#{game_id}", "game_over", %{
          reason: state.game_over_reason,
          winner_player_id: state.winner_player_id
        })
      end

      :ok
    else
      error ->
        Logger.error("Falha ao calcular/aplicar lance do bot em #{game_id}: #{inspect(error)}")
        GameServer.bot_move_failed(game_id, fen, token)
    end
  end

  defp promotion_or_nil(""), do: nil
  defp promotion_or_nil(value), do: value
end
