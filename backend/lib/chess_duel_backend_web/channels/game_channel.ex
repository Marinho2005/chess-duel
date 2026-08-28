defmodule ChessDuelBackendWeb.GameChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games.GameServer

  @impl true
  def join("game:" <> game_id, _payload, socket) do
    player_id = socket.assigns.user_id

    with {:ok, %{color: color, state: state}} <-
           GameServer.player_connected(game_id, player_id, socket.assigns.identity_type),
         true <- color in ["white", "black"] do
      socket =
        socket
        |> assign(:game_id, game_id)
        |> assign(:player_color, color)

      {:ok, public_state(state, color), socket}
    else
      {:error, :game_full} -> {:error, %{reason: "game_full"}}
      {:error, :identity_mismatch} -> {:error, %{reason: "identity_mismatch"}}
      {:error, :game_not_found} -> {:error, %{reason: "game_not_found"}}
      false -> {:error, %{reason: "not_a_player"}}
      {:error, reason} -> {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if game_id = socket.assigns[:game_id] do
      GameServer.player_disconnected(game_id, socket.assigns.user_id)
    end

    :ok
  end

  @impl true
  def handle_in("move", %{"from" => from, "to" => to} = payload, socket) do
    game_id = socket.assigns.game_id
    player = socket.assigns.user_id
    promotion = Map.get(payload, "promotion")

    case GameServer.make_move(game_id, from, to, player, promotion) do
      {:ok, state} ->
        broadcast!(socket, "move_made", %{
          from: from,
          to: to,
          player: player,
          promotion: promotion,
          new_fen: state.fen,
          current_turn: state.current_turn,
          is_check: state.is_check,
          is_checkmate: state.is_checkmate,
          is_stalemate: state.is_stalemate,
          is_draw: state.is_draw,
          white_time_remaining_ms: state.white_time_remaining_ms,
          black_time_remaining_ms: state.black_time_remaining_ms
        })

        maybe_broadcast_game_over(socket, state, player)

        {:reply, {:ok, %{current_turn: state.current_turn}}, socket}

      {:error, :illegal_move} ->
        {:reply, {:error, %{reason: "illegal_move"}}, socket}

      {:error, :not_your_turn} ->
        {:reply, {:error, %{reason: "not_your_turn"}}, socket}

      {:error, :not_a_player} ->
        {:reply, {:error, %{reason: "not_a_player"}}, socket}

      {:error, :game_finished} ->
        {:reply, {:error, %{reason: "game_finished"}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("move", _payload, socket) do
    {:reply, {:error, %{reason: "from and to are required"}}, socket}
  end

  defp public_state(state, player_color) do
    %{
      moves: state.moves,
      current_turn: state.current_turn,
      fen: state.fen,
      status: state.status,
      game_over_reason: state.game_over_reason,
      winner_player_id: state.winner_player_id,
      player_color: player_color,
      white_player_id: state.white_player_id,
      black_player_id: state.black_player_id,
      white_player: public_player(state, :white),
      black_player: public_player(state, :black),
      guest_game: state.game_type == :guest,
      is_check: state.is_check,
      is_checkmate: state.is_checkmate,
      is_stalemate: state.is_stalemate,
      is_draw: state.is_draw,
      white_time_remaining_ms: state.white_time_remaining_ms,
      black_time_remaining_ms: state.black_time_remaining_ms,
      initial_time_ms: state.initial_time_ms,
      increment_ms: state.increment_ms
    }
  end

  defp public_player(%{game_type: :guest} = state, :white), do: state.white_player
  defp public_player(%{game_type: :guest} = state, :black), do: state.black_player

  defp public_player(state, :white), do: registered_player(state.white_player_id)
  defp public_player(state, :black), do: registered_player(state.black_player_id)

  defp registered_player(nil), do: nil

  defp registered_player(user_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      %{id: user.id, nickname: user.nickname, rating: user.rating, avatar_url: user.avatar_path}
    else
      _ -> nil
    end
  end

  defp maybe_broadcast_game_over(socket, state, player) do
    cond do
      state.is_checkmate ->
        broadcast!(socket, "game_over", %{reason: "checkmate", winner_player_id: player})

      state.is_stalemate ->
        broadcast!(socket, "game_over", %{reason: "stalemate", winner_player_id: nil})

      state.is_draw ->
        broadcast!(socket, "game_over", %{reason: "draw", winner_player_id: nil})

      true ->
        :ok
    end
  end
end
