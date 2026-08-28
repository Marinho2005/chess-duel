defmodule ChessDuelBackend.Games.GameServer do
  use GenServer, restart: :transient

  alias ChessDuelBackend.{GameRegistry, GameSupervisor}
  alias ChessDuelBackend.ChessValidator
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Ratings

  require Logger

  @initial_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  # Fallback para partidas iniciadas fora do lobby e para testes manuais curtos.
  @default_initial_time_ms 180_000
  @default_abandonment_grace_ms 60_000

  def start_link(game_id) when is_binary(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def start_link({game_id, time_control}) do
    GenServer.start_link(__MODULE__, {game_id, time_control}, name: via_tuple(game_id))
  end

  def start_link({game_id, time_control, game_type}) do
    GenServer.start_link(__MODULE__, {game_id, time_control, game_type}, name: via_tuple(game_id))
  end

  def child_spec(game_id) do
    {id, start_arg} =
      case game_id do
        {id, _time_control, _game_type} = args -> {id, args}
        {id, _time_control} = args -> {id, args}
        id -> {id, id}
      end

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [start_arg]},
      restart: :transient
    }
  end

  def start_or_get(game_id, time_control \\ nil, game_type \\ :registered)
      when is_binary(game_id) do
    case Registry.lookup(GameRegistry, game_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        child_arg =
          if time_control || game_type != :registered,
            do: {game_id, time_control, game_type},
            else: game_id

        case DynamicSupervisor.start_child(GameSupervisor, {__MODULE__, child_arg}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  def make_move(game_id, from, to, player) do
    make_move(game_id, from, to, player, nil)
  end

  def make_move(game_id, from, to, player, promotion) do
    with {:ok, pid} <- start_or_get(game_id) do
      GenServer.call(pid, {:make_move, from, to, player, promotion}, 7_000)
    end
  end

  def player_connected(game_id, player_id, identity_type \\ :user)

  def player_connected(game_id, player_id, :guest) do
    case Registry.lookup(GameRegistry, game_id) do
      [{pid, _value}] -> GenServer.call(pid, {:player_connected, player_id, :guest})
      [] -> {:error, :game_not_found}
    end
  end

  def player_connected(game_id, player_id, :user) do
    with {:ok, pid} <- start_or_get(game_id) do
      GenServer.call(pid, {:player_connected, player_id, :user})
    end
  end

  def reserve_players(game_id, white_player_id, black_player_id) do
    reserve_players(game_id, white_player_id, black_player_id, nil)
  end

  def reserve_players(game_id, white_player_id, black_player_id, time_control) do
    with {:ok, pid} <- start_or_get(game_id, time_control) do
      GenServer.call(pid, {:reserve_players, white_player_id, black_player_id})
    end
  end

  def reserve_guest_players(game_id, white_guest, black_guest, time_control) do
    with {:ok, pid} <- start_or_get(game_id, time_control, :guest) do
      GenServer.call(pid, {:reserve_guest_players, white_guest, black_guest})
    end
  end

  def player_disconnected(game_id, player_id) do
    with {:ok, pid} <- start_or_get(game_id) do
      GenServer.cast(pid, {:player_disconnected, player_id})
    end
  end

  def get_state(game_id) do
    with {:ok, pid} <- start_or_get(game_id) do
      GenServer.call(pid, :get_state)
    end
  end

  @impl true
  def init(game_id) when is_binary(game_id), do: init({game_id, nil, :registered})

  def init({game_id, time_control}), do: init({game_id, time_control, :registered})

  def init({game_id, time_control, game_type}) do
    configured_initial_time_ms =
      Application.get_env(
        :chess_duel_backend,
        :game_clock_initial_ms,
        @default_initial_time_ms
      )

    initial_time_ms =
      if time_control, do: time_control.initial_time_ms, else: configured_initial_time_ms

    increment_ms = if time_control, do: time_control.increment_ms, else: 0

    abandonment_grace_ms =
      Application.get_env(
        :chess_duel_backend,
        :game_abandonment_grace_ms,
        @default_abandonment_grace_ms
      )

    initial_state = %{
      game_id: game_id,
      game_type: game_type,
      white_player_id: nil,
      black_player_id: nil,
      white_player: nil,
      black_player: nil,
      connected_player_counts: %{},
      abandonment_timer_refs: %{},
      abandonment_grace_ms: abandonment_grace_ms,
      moves: [],
      current_turn: "white",
      fen: @initial_fen,
      status: "waiting",
      game_over_reason: nil,
      winner_player_id: nil,
      is_check: false,
      is_checkmate: false,
      is_stalemate: false,
      is_draw: false,
      white_time_remaining_ms: initial_time_ms,
      black_time_remaining_ms: initial_time_ms,
      initial_time_ms: initial_time_ms,
      increment_ms: increment_ms,
      turn_started_at: nil,
      clock_timer_ref: nil,
      persistence_pid: nil
    }

    if game_type == :guest do
      {:ok, initial_state}
    else
      init_persisted_game(initial_state)
    end
  end

  defp init_persisted_game(initial_state) do
    initial_attrs = persistence_attrs(initial_state)

    case Games.get_or_create_game(initial_state.game_id, initial_attrs) do
      {:ok, game} ->
        game_server_pid = self()

        persistence_pid =
          spawn(fn ->
            monitor_ref = Process.monitor(game_server_pid)
            maybe_rate_game(game)
            persistence_loop(game, monitor_ref)
          end)

        state =
          initial_state
          |> restore_from_game(game)
          |> Map.put(:persistence_pid, persistence_pid)
          |> resume_clock_after_restore()

        {:ok, state}

      {:error, changeset} ->
        {:stop, {:game_persistence_failed, changeset}}
    end
  end

  @impl true
  def handle_call(
        {:reserve_players, white_player_id, black_player_id},
        _from,
        %{game_type: :registered, white_player_id: nil, black_player_id: nil, moves: []} = state
      ) do
    state = %{state | white_player_id: white_player_id, black_player_id: black_player_id}
    persist_state(state)
    {:reply, {:ok, snapshot_clock(state)}, state}
  end

  def handle_call(
        {:reserve_players, white_player_id, black_player_id},
        _from,
        %{
          game_type: :registered,
          white_player_id: white_player_id,
          black_player_id: black_player_id
        } = state
      ) do
    {:reply, {:ok, snapshot_clock(state)}, state}
  end

  def handle_call(
        {:reserve_players, _white_player_id, _black_player_id},
        _from,
        %{game_type: :registered} = state
      ) do
    {:reply, {:error, :game_full}, state}
  end

  def handle_call({:reserve_players, _white_player_id, _black_player_id}, _from, state) do
    {:reply, {:error, :identity_mismatch}, state}
  end

  def handle_call(
        {:reserve_guest_players, white_guest, black_guest},
        _from,
        %{game_type: :guest, white_player_id: nil, black_player_id: nil, moves: []} = state
      ) do
    state = %{
      state
      | white_player_id: white_guest.id,
        black_player_id: black_guest.id,
        white_player: public_guest(white_guest),
        black_player: public_guest(black_guest)
    }

    {:reply, {:ok, snapshot_clock(state)}, state}
  end

  def handle_call({:reserve_guest_players, _white, _black}, _from, state) do
    {:reply, {:error, :identity_mismatch}, state}
  end

  def handle_call(
        {:make_move, _from, _to, _player, _promotion},
        _caller,
        %{status: "finished"} = state
      ) do
    {:reply, {:error, :game_finished}, state}
  end

  def handle_call({:make_move, from, to, player, promotion}, _caller, state) do
    case player_color(state, player) do
      nil ->
        {:reply, {:error, :not_a_player}, state}

      color when color != state.current_turn ->
        {:reply, {:error, :not_your_turn}, state}

      _color ->
        validate_and_apply_move(from, to, player, promotion, state)
    end
  end

  def handle_call(
        {:player_connected, _player_id, identity_type},
        _from,
        state
      )
      when (identity_type == :guest and state.game_type != :guest) or
             (identity_type == :user and state.game_type != :registered) do
    {:reply, {:error, :identity_mismatch}, state}
  end

  def handle_call(
        {:player_connected, player_id, _identity_type},
        _from,
        %{status: "finished"} = state
      ) do
    {:reply, {:ok, %{color: player_color(state, player_id), state: snapshot_clock(state)}}, state}
  end

  def handle_call({:player_connected, player_id, _identity_type}, _from, state) do
    case player_color(state, player_id) || next_open_color(state) do
      nil ->
        {:reply, {:error, :game_full}, state}

      color ->
        state =
          state
          |> assign_player_if_needed(color, player_id)
          |> increment_connection(player_id)
          |> cancel_abandonment_timer(color)

        persist_state(state)

        {:reply, {:ok, %{color: color, state: snapshot_clock(state)}}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, snapshot_clock(state)}, state}
  end

  @impl true
  def handle_cast({:player_disconnected, _player_id}, %{status: "finished"} = state) do
    {:noreply, state}
  end

  def handle_cast({:player_disconnected, player_id}, state) do
    color = player_color(state, player_id)

    state =
      state
      |> decrement_connection(player_id)
      |> maybe_schedule_abandonment(color)

    {:noreply, state}
  end

  defp validate_and_apply_move(from, to, player, promotion, state) do
    case ChessValidator.validate_move(state.fen, from, to, promotion) do
      {:ok, result} ->
        now = System.monotonic_time(:millisecond)

        case debit_current_clock(state, now) do
          {:expired, expired_state} ->
            finished_state = finish_by_timeout(expired_state)
            {:reply, {:error, :game_finished}, finished_state}

          {:ok, clock_state} ->
            move = %{
              from: from,
              to: to,
              player: player,
              promotion: promotion,
              captured: result.captured,
              timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
            }

            next_turn = opposite_color(state.current_turn)
            finished = result.is_checkmate or result.is_stalemate or result.is_draw
            winner_player_id = if result.is_checkmate, do: player

            cancel_clock_timer(clock_state.clock_timer_ref)

            new_state =
              clock_state
              |> add_increment(state.current_turn)
              |> Map.merge(%{
                moves: state.moves ++ [move],
                current_turn: next_turn,
                fen: result.new_fen,
                status: if(finished, do: "finished", else: "in_progress"),
                game_over_reason: game_over_reason(result),
                winner_player_id: winner_player_id,
                is_check: result.is_check,
                is_checkmate: result.is_checkmate,
                is_stalemate: result.is_stalemate,
                is_draw: result.is_draw,
                turn_started_at: now,
                clock_timer_ref: nil
              })
              |> schedule_current_clock_unless_finished()

            persist_state(new_state)

            {:reply, {:ok, snapshot_clock(new_state, now)}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:time_expired, %{status: "finished"} = state), do: {:noreply, state}

  def handle_info({:abandonment_expired, _color}, %{status: "finished"} = state) do
    {:noreply, state}
  end

  def handle_info({:abandonment_expired, color}, state) do
    {:noreply, finish_by_abandonment(state, color)}
  end

  def handle_info(:time_expired, state) do
    now = System.monotonic_time(:millisecond)

    case debit_current_clock(state, now) do
      {:expired, expired_state} ->
        {:noreply, finish_by_timeout(expired_state)}

      {:ok, updated_state} ->
        # Protecao para um timer antigo que ja estava na mailbox ao ser cancelado.
        {:noreply, schedule_current_clock(%{updated_state | turn_started_at: now})}
    end
  end

  defp debit_current_clock(%{turn_started_at: nil} = state, _now), do: {:ok, state}

  defp debit_current_clock(%{status: "finished"} = state, _now), do: {:ok, state}

  defp debit_current_clock(state, now) do
    elapsed_ms = max(now - state.turn_started_at, 0)
    time_key = time_key(state.current_turn)
    remaining_ms = max(Map.fetch!(state, time_key) - elapsed_ms, 0)
    updated_state = Map.put(state, time_key, remaining_ms)

    if remaining_ms == 0, do: {:expired, updated_state}, else: {:ok, updated_state}
  end

  defp add_increment(state, color) do
    time_key = time_key(color)
    Map.update!(state, time_key, &(&1 + state.increment_ms))
  end

  defp snapshot_clock(state, now \\ System.monotonic_time(:millisecond)) do
    case debit_current_clock(state, now) do
      {:ok, snapshot} -> snapshot
      {:expired, snapshot} -> snapshot
    end
  end

  defp schedule_current_clock_unless_finished(%{status: "finished"} = state), do: state
  defp schedule_current_clock_unless_finished(state), do: schedule_current_clock(state)

  defp schedule_current_clock(state) do
    remaining_ms = Map.fetch!(state, time_key(state.current_turn))
    timer_ref = Process.send_after(self(), :time_expired, remaining_ms)
    %{state | clock_timer_ref: timer_ref}
  end

  defp cancel_clock_timer(nil), do: :ok
  defp cancel_clock_timer(timer_ref), do: Process.cancel_timer(timer_ref)

  defp finish_by_timeout(state) do
    cancel_clock_timer(state.clock_timer_ref)
    winner = opposite_color(state.current_turn)

    winner_player_id = player_id_for_color(state, winner)
    finished_state = finish_state(state, "timeout", winner_player_id)

    persist_state(finished_state)
    broadcast_game_over(finished_state, "timeout", winner_player_id)
    finished_state
  end

  defp finish_by_abandonment(state, abandoned_color) do
    state = snapshot_clock(state)

    winner_player_id =
      abandoned_color
      |> opposite_color()
      |> then(fn color ->
        player_id = player_id_for_color(state, color)

        if connected_count(state, player_id) > 0 do
          player_id
        end
      end)

    finished_state = finish_state(state, "abandonment", winner_player_id)

    persist_state(finished_state)
    broadcast_game_over(finished_state, "abandonment", winner_player_id)
    finished_state
  end

  defp finish_state(state, reason, winner_player_id) do
    cancel_clock_timer(state.clock_timer_ref)

    Enum.each(state.abandonment_timer_refs, fn {_color, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    %{
      state
      | status: "finished",
        game_over_reason: reason,
        winner_player_id: winner_player_id,
        clock_timer_ref: nil,
        turn_started_at: nil,
        abandonment_timer_refs: %{}
    }
  end

  defp broadcast_game_over(state, reason, winner_player_id) do
    topic = "game:#{state.game_id}"

    Phoenix.PubSub.broadcast(
      ChessDuelBackend.PubSub,
      topic,
      %Phoenix.Socket.Broadcast{
        topic: topic,
        event: "game_over",
        payload: %{reason: reason, winner_player_id: winner_player_id}
      }
    )
  end

  defp time_key("white"), do: :white_time_remaining_ms
  defp time_key("black"), do: :black_time_remaining_ms

  defp opposite_color("white"), do: "black"
  defp opposite_color("black"), do: "white"

  defp game_over_reason(%{is_checkmate: true}), do: "checkmate"
  defp game_over_reason(%{is_stalemate: true}), do: "stalemate"
  defp game_over_reason(%{is_draw: true}), do: "draw"
  defp game_over_reason(_result), do: nil

  defp next_open_color(%{white_player_id: nil}), do: "white"
  defp next_open_color(%{black_player_id: nil}), do: "black"
  defp next_open_color(_state), do: nil

  defp player_color(%{white_player_id: player_id}, player_id) when is_binary(player_id), do: "white"
  defp player_color(%{black_player_id: player_id}, player_id) when is_binary(player_id), do: "black"
  defp player_color(_state, _player_id), do: nil

  defp player_id_for_color(state, "white"), do: state.white_player_id
  defp player_id_for_color(state, "black"), do: state.black_player_id

  defp assign_player_if_needed(%{white_player_id: nil} = state, "white", player_id) do
    %{state | white_player_id: player_id}
  end

  defp assign_player_if_needed(%{black_player_id: nil} = state, "black", player_id) do
    %{state | black_player_id: player_id}
  end

  defp assign_player_if_needed(state, _color, _player_id), do: state

  defp public_guest(guest) do
    %{id: guest.id, nickname: guest.nickname, rating: nil, avatar_url: nil, guest: true}
  end

  defp increment_connection(state, player_id) do
    update_in(state.connected_player_counts, fn counts ->
      Map.update(counts, player_id, 1, &(&1 + 1))
    end)
  end

  defp decrement_connection(state, player_id) do
    update_in(state.connected_player_counts, fn counts ->
      Map.update(counts, player_id, 0, &max(&1 - 1, 0))
    end)
  end

  defp connected_count(_state, nil), do: 0
  defp connected_count(state, player_id), do: Map.get(state.connected_player_counts, player_id, 0)

  defp maybe_schedule_abandonment(state, nil), do: state

  defp maybe_schedule_abandonment(state, color) do
    player_id = player_id_for_color(state, color)

    cond do
      connected_count(state, player_id) > 0 ->
        state

      Map.has_key?(state.abandonment_timer_refs, color) ->
        state

      true ->
        # O Channel notifica saida explicitamente; o GenServer centraliza a janela de reconexao.
        timer_ref =
          Process.send_after(self(), {:abandonment_expired, color}, state.abandonment_grace_ms)

        put_in(state.abandonment_timer_refs[color], timer_ref)
    end
  end

  defp cancel_abandonment_timer(state, color) do
    case Map.pop(state.abandonment_timer_refs, color) do
      {nil, _refs} ->
        state

      {timer_ref, refs} ->
        Process.cancel_timer(timer_ref)
        %{state | abandonment_timer_refs: refs}
    end
  end

  defp persist_state(%{persistence_pid: persistence_pid} = state)
       when is_pid(persistence_pid) do
    send(persistence_pid, {:persist, persistence_attrs(state)})
    :ok
  end

  defp persist_state(_state), do: :ok

  defp persistence_attrs(state) do
    attrs = %{
      status: state.status,
      current_turn: state.current_turn,
      white_player_id: state.white_player_id,
      black_player_id: state.black_player_id,
      moves: state.moves,
      final_fen: state.fen,
      white_time_remaining_ms: state.white_time_remaining_ms,
      black_time_remaining_ms: state.black_time_remaining_ms,
      initial_time_ms: state.initial_time_ms,
      increment_ms: state.increment_ms
    }

    if state.status == "finished" do
      Map.merge(attrs, %{
        result: persisted_result(state),
        end_reason: state.game_over_reason,
        finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    else
      attrs
    end
  end

  defp persistence_loop(game, monitor_ref) do
    receive do
      {:persist, attrs} ->
        next_game =
          case safely_update_game(game, attrs) do
            {:ok, updated_game} ->
              maybe_rate_game(updated_game)
              updated_game

            {:error, changeset} ->
              Logger.error(
                "Nao foi possivel persistir a partida #{game.game_id}: #{inspect(changeset)}"
              )

              game
          end

        persistence_loop(next_game, monitor_ref)

      {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
        :ok
    end
  end

  defp safely_update_game(game, attrs) do
    Games.update_game(game, attrs)
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    :exit, reason -> {:error, reason}
  end

  defp persisted_result(%{game_over_reason: "abandonment", winner_player_id: nil}),
    do: "abandoned"

  defp persisted_result(%{game_over_reason: reason}) when reason in ["stalemate", "draw"],
    do: "draw"

  defp persisted_result(state) do
    case player_color(state, state.winner_player_id) do
      "white" -> "white_wins"
      "black" -> "black_wins"
      nil -> "draw"
    end
  end

  defp maybe_rate_game(%{status: "finished", rated_at: nil} = game) do
    case Ratings.rate_game(game.game_id) do
      {:ok, %{white: white, black: black} = rating} ->
        ChessDuelBackendWeb.Endpoint.broadcast("game:#{game.game_id}", "rating_updated", rating)

        Logger.info(
          "Rating atualizado na partida #{game.game_id}: " <>
            "#{white.before}->#{white.after}, #{black.before}->#{black.after}"
        )

      {:ok, :already_rated} ->
        :ok

      {:error, reason} when reason in [:game_not_rateable, :invalid_players, :players_not_found] ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Nao foi possivel calcular rating da partida #{game.game_id}: #{inspect(reason)}"
        )
    end
  end

  defp maybe_rate_game(_game), do: :ok

  defp restore_from_game(state, game) do
    %{
      state
      | white_player_id: game.white_player_id,
        black_player_id: game.black_player_id,
        moves: normalize_moves(game.moves || []),
        current_turn: game.current_turn,
        fen: game.final_fen || @initial_fen,
        status: game.status,
        game_over_reason: game.end_reason,
        winner_player_id: restored_winner_player_id(game),
        is_checkmate: game.end_reason == "checkmate",
        is_stalemate: game.end_reason == "stalemate",
        is_draw: game.end_reason == "draw",
        white_time_remaining_ms: game.white_time_remaining_ms || state.white_time_remaining_ms,
        black_time_remaining_ms: game.black_time_remaining_ms || state.black_time_remaining_ms,
        initial_time_ms: game.initial_time_ms || state.initial_time_ms,
        increment_ms: game.increment_ms || state.increment_ms
    }
  end

  defp normalize_moves(moves) do
    Enum.map(moves, fn move ->
      %{
        from: move[:from] || move["from"],
        to: move[:to] || move["to"],
        player: move[:player] || move["player"],
        promotion: move[:promotion] || move["promotion"],
        captured: move[:captured] || move["captured"],
        timestamp: move[:timestamp] || move["timestamp"]
      }
    end)
  end

  defp restored_winner_player_id(%{result: "white_wins"} = game), do: game.white_player_id
  defp restored_winner_player_id(%{result: "black_wins"} = game), do: game.black_player_id
  defp restored_winner_player_id(_game), do: nil

  defp resume_clock_after_restore(%{status: "in_progress"} = state) do
    state
    |> Map.put(:turn_started_at, System.monotonic_time(:millisecond))
    |> schedule_current_clock()
  end

  defp resume_clock_after_restore(state), do: state

  defp via_tuple(game_id), do: {:via, Registry, {GameRegistry, game_id}}
end
