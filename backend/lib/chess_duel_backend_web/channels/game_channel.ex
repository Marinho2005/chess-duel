defmodule ChessDuelBackendWeb.GameChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Games.GameServer

  @impl true
  def join("game:" <> game_id, _payload, socket) do
    with {:ok, _pid} <- GameServer.start_or_get(game_id),
         {:ok, state} <- GameServer.get_state(game_id) do
      socket = assign(socket, :game_id, game_id)
      {:ok, public_state(state), socket}
    else
      {:error, reason} -> {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def handle_in("move", %{"from" => from, "to" => to} = payload, socket) do
    game_id = socket.assigns.game_id
    player = socket.assigns.player_id
    promotion = Map.get(payload, "promotion")

    case GameServer.make_move(game_id, from, to, player, promotion) do
      {:ok, state} ->
        broadcast!(socket, "move_made", %{
          from: from,
          to: to,
          player: player,
          new_fen: state.fen,
          current_turn: state.current_turn,
          is_check: state.is_check,
          is_checkmate: state.is_checkmate,
          is_stalemate: state.is_stalemate,
          is_draw: state.is_draw
        })

        maybe_broadcast_game_over(socket, state, player)

        {:reply, {:ok, %{current_turn: state.current_turn}}, socket}

      {:error, :illegal_move} ->
        {:reply, {:error, %{reason: "illegal_move"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("move", _payload, socket) do
    {:reply, {:error, %{reason: "from and to are required"}}, socket}
  end

  defp public_state(state) do
    %{
      moves: state.moves,
      current_turn: state.current_turn,
      fen: state.fen,
      status: state.status,
      is_check: state.is_check,
      is_checkmate: state.is_checkmate,
      is_stalemate: state.is_stalemate,
      is_draw: state.is_draw
    }
  end

  defp maybe_broadcast_game_over(socket, state, player) do
    cond do
      state.is_checkmate ->
        broadcast!(socket, "game_over", %{reason: "checkmate", winner: player})

      state.is_stalemate ->
        broadcast!(socket, "game_over", %{reason: "stalemate", winner: nil})

      state.is_draw ->
        broadcast!(socket, "game_over", %{reason: "draw", winner: nil})

      true ->
        :ok
    end
  end
end
