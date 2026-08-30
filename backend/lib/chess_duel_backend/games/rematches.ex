defmodule ChessDuelBackend.Games.Rematches do
  @moduledoc "Coordena convites efêmeros de revanche sem reabrir a partida encerrada."

  use GenServer

  alias ChessDuelBackend.Games.{Bots, GameServer, TimeControl}

  @offer_ttl_ms :timer.minutes(5)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def request(game_id, player_id), do: GenServer.call(__MODULE__, {:request, game_id, player_id})
  def accept(game_id, player_id), do: GenServer.call(__MODULE__, {:accept, game_id, player_id})
  def decline(game_id, player_id), do: GenServer.call(__MODULE__, {:decline, game_id, player_id})

  def accept_bot(game_id, player_id),
    do: GenServer.call(__MODULE__, {:accept_bot, game_id, player_id})

  def status(game_id, player_id), do: GenServer.call(__MODULE__, {:status, game_id, player_id})

  @impl true
  def init(opts), do: {:ok, %{offers: %{}, ttl_ms: Keyword.get(opts, :ttl_ms, @offer_ttl_ms)}}

  @impl true
  def handle_call({:request, game_id, player_id}, _from, state) do
    with {:ok, game} <- finished_human_game(game_id, player_id) do
      case state.offers[game_id] do
        %{new_game_id: new_game_id} ->
          {:reply, {:ok, %{status: "started", game_id: new_game_id}}, state}

        %{requester_id: ^player_id} ->
          {:reply, {:ok, %{status: "waiting"}}, state}

        %{requester_id: _opponent_id} ->
          start_human_rematch(game_id, player_id, game, state)

        nil ->
          timer_ref = Process.send_after(self(), {:expire, game_id}, state.ttl_ms)
          offer = %{requester_id: player_id, timer_ref: timer_ref}
          broadcast(game_id, "rematch_offered", %{requester_player_id: player_id})
          {:reply, {:ok, %{status: "waiting"}}, put_in(state.offers[game_id], offer)}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:accept, game_id, player_id}, _from, state) do
    with {:ok, game} <- finished_human_game(game_id, player_id) do
      case state.offers[game_id] do
        %{new_game_id: new_game_id} ->
          {:reply, {:ok, %{status: "started", game_id: new_game_id}}, state}

        %{requester_id: ^player_id} ->
          {:reply, {:error, :cannot_accept_own_offer}, state}

        %{requester_id: _requester_id} ->
          start_human_rematch(game_id, player_id, game, state)

        nil ->
          {:reply, {:error, :offer_not_found}, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:decline, game_id, player_id}, _from, state) do
    with {:ok, _game} <- finished_human_game(game_id, player_id) do
      case state.offers[game_id] do
        %{new_game_id: _new_game_id} ->
          {:reply, {:error, :rematch_already_started}, state}

        %{requester_id: ^player_id} ->
          {:reply, {:error, :cannot_decline_own_offer}, state}

        %{timer_ref: timer_ref} ->
          Process.cancel_timer(timer_ref)
          broadcast(game_id, "rematch_declined", %{player_id: player_id})
          {:reply, :ok, update_in(state.offers, &Map.delete(&1, game_id))}

        nil ->
          {:reply, {:error, :offer_not_found}, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:accept_bot, game_id, player_id}, _from, state) do
    case state.offers[game_id] do
      %{new_game_id: new_game_id} ->
        {:reply, {:ok, %{status: "started", game_id: new_game_id}}, state}

      _ ->
        with {:ok, game} <- finished_bot_game(game_id, player_id),
             human_color when human_color in ["white", "black"] <- player_color(game, player_id),
             bot when not is_nil(bot) <- game.bot || Bots.get(game.bot_id),
             new_game_id = Ecto.UUID.generate(),
             {:ok, _new_state} <-
               GameServer.reserve_bot_game(
                 new_game_id,
                 player_id,
                 bot,
                 opposite_color(human_color),
                 time_control(game)
               ) do
          timer_ref = Process.send_after(self(), {:expire, game_id}, state.ttl_ms)
          completed = %{requester_id: player_id, timer_ref: timer_ref, new_game_id: new_game_id}
          broadcast(game_id, "rematch_started", %{game_id: new_game_id})

          {:reply, {:ok, %{status: "started", game_id: new_game_id}},
           put_in(state.offers[game_id], completed)}
        else
          nil -> {:reply, {:error, :rematch_unavailable}, state}
          error -> {:reply, error, state}
        end
    end
  end

  def handle_call({:status, game_id, player_id}, _from, state) do
    status =
      case state.offers[game_id] do
        %{new_game_id: new_game_id} -> %{status: "started", game_id: new_game_id}
        %{requester_id: ^player_id} -> %{status: "waiting"}
        %{requester_id: _other} -> %{status: "incoming"}
        nil -> %{status: "idle"}
      end

    {:reply, status, state}
  end

  @impl true
  def handle_info({:expire, game_id}, state) do
    case state.offers[game_id] do
      %{new_game_id: _new_game_id} -> :ok
      %{requester_id: _requester_id} -> broadcast(game_id, "rematch_expired", %{})
      nil -> :ok
    end

    {:noreply, update_in(state.offers, &Map.delete(&1, game_id))}
  end

  defp start_human_rematch(original_id, _accepter_id, game, state) do
    offer = state.offers[original_id]
    Process.cancel_timer(offer.timer_ref)
    new_game_id = Ecto.UUID.generate()

    reservation =
      case game.game_type do
        :guest ->
          GameServer.reserve_guest_players(
            new_game_id,
            game.black_player,
            game.white_player,
            time_control(game)
          )

        :registered ->
          GameServer.reserve_players(
            new_game_id,
            game.black_player_id,
            game.white_player_id,
            time_control(game)
          )
      end

    case reservation do
      {:ok, _new_state} ->
        timer_ref = Process.send_after(self(), {:expire, original_id}, state.ttl_ms)
        completed = offer |> Map.put(:new_game_id, new_game_id) |> Map.put(:timer_ref, timer_ref)
        broadcast(original_id, "rematch_started", %{game_id: new_game_id})

        {:reply, {:ok, %{status: "started", game_id: new_game_id}},
         put_in(state.offers[original_id], completed)}

      error ->
        {:reply, error, state}
    end
  end

  defp finished_human_game(game_id, player_id) do
    with {:ok, game} <- GameServer.get_state(game_id),
         true <- game.status == "finished",
         true <- game.game_type in [:registered, :guest],
         true <- not is_nil(player_color(game, player_id)) do
      {:ok, game}
    else
      false -> {:error, :rematch_unavailable}
      error -> error
    end
  end

  defp finished_bot_game(game_id, player_id) do
    with {:ok, game} <- GameServer.get_state(game_id),
         true <- game.status == "finished",
         true <- game.game_type == :bot,
         true <- not is_nil(player_color(game, player_id)) do
      {:ok, game}
    else
      false -> {:error, :rematch_unavailable}
      error -> error
    end
  end

  defp player_color(%{white_player_id: player_id}, player_id), do: "white"
  defp player_color(%{black_player_id: player_id}, player_id), do: "black"
  defp player_color(_game, _player_id), do: nil

  defp time_control(game), do: TimeControl.from_values(game.initial_time_ms, game.increment_ms)
  defp opposite_color("white"), do: "black"
  defp opposite_color("black"), do: "white"

  defp broadcast(game_id, event, payload) do
    ChessDuelBackendWeb.Endpoint.broadcast("game:#{game_id}", event, payload)
  end
end
