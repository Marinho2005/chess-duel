defmodule ChessDuelBackend.Puzzles.BattleServer do
  use GenServer

  alias ChessDuelBackend.Puzzles
  alias ChessDuelBackend.Puzzles.Battles

  @retention_ms 300_000

  def child_spec(opts),
    do: %{
      id: {__MODULE__, opts[:battle].id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }

  def create(player_one, player_two, duration_seconds) do
    with {:ok, setup} <- Battles.create(player_one, player_two, duration_seconds),
         {:ok, _pid} <-
           DynamicSupervisor.start_child(
             ChessDuelBackend.PuzzleBattleSupervisor,
             {__MODULE__, setup}
           ) do
      {:ok, setup.battle.id}
    end
  end

  def snapshot(battle_id, user_id), do: call_battle(battle_id, {:snapshot, user_id})

  def attempt(battle_id, user_id, index, move),
    do: call_battle(battle_id, {:attempt, user_id, index, move})

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {ChessDuelBackend.PuzzleBattleRegistry, opts.battle.id}}
    )
  end

  @impl true
  def init(setup) do
    battle = setup.battle
    now = DateTime.utc_now(:millisecond)
    start_delay = max(DateTime.diff(battle.started_at, now, :millisecond), 0)
    end_delay = max(DateTime.diff(battle.ends_at, now, :millisecond), 0)
    Process.send_after(self(), :begin, start_delay)
    timer = Process.send_after(self(), :expire, end_delay)
    players = Map.new(setup.players, &{&1.id, &1})

    participant_states =
      Map.new(setup.participants, fn participant ->
        {participant.user_id,
         %{
           slot: participant.slot,
           score: 0,
           errors: 0,
           puzzles_attempted: 0,
           puzzle_index: 0,
           expected_index: 1,
           complete: false
         }}
      end)

    {:ok,
     %{
       battle: battle,
       puzzles: setup.puzzles,
       players: players,
       participant_states: participant_states,
       timer: timer,
       result: nil
     }}
  end

  @impl true
  def handle_call({:snapshot, user_id}, _from, state) do
    if Map.has_key?(state.players, user_id) do
      state = maybe_finish(state)
      {:reply, {:ok, snapshot_payload(state, user_id)}, state}
    else
      {:reply, {:error, :forbidden}, state}
    end
  end

  def handle_call({:attempt, user_id, index, move}, _from, state) do
    participant = state.participant_states[user_id]

    cond do
      is_nil(participant) ->
        {:reply, {:error, :forbidden}, state}

      state.result || DateTime.compare(DateTime.utc_now(), state.battle.ends_at) != :lt ->
        state = finish(state)
        {:reply, {:ok, snapshot_payload(state, user_id)}, state}

      DateTime.compare(DateTime.utc_now(), state.battle.started_at) == :lt ->
        {:reply, {:error, :not_started}, state}

      participant.complete ->
        {:reply, {:error, :sequence_complete}, state}

      index != participant.expected_index ->
        {:reply, {:error, {:unexpected_index, participant.expected_index}}, state}

      true ->
        validate_move(state, user_id, participant, index, move)
    end
  end

  @impl true
  def handle_info(:begin, state) do
    Battles.mark_started(state.battle.id)
    broadcast(state, "battle_started", public_progress(state))
    {:noreply, state}
  end

  def handle_info(:expire, state) do
    state = finish(state)
    Process.send_after(self(), :stop, @retention_ms)
    {:noreply, state}
  end

  def handle_info(:stop, state), do: {:stop, :normal, state}

  defp validate_move(state, user_id, participant, index, move) do
    puzzle = Enum.at(state.puzzles, participant.puzzle_index)

    cond do
      Enum.at(puzzle.moves, index) != move ->
        advance_participant(state, user_id, participant, :incorrect)

      index == length(puzzle.moves) - 1 ->
        advance_participant(state, user_id, participant, :correct)

      true ->
        automatic_index = index + 1
        next_index = index + 2

        if next_index >= length(puzzle.moves) do
          advance_participant(state, user_id, participant, :correct)
        else
          updated = %{participant | expected_index: next_index}
          state = put_in(state.participant_states[user_id], updated)

          payload =
            base_attempt_payload(state, user_id, :correct)
            |> Map.merge(%{
              resolved: false,
              automatic_move: Enum.at(puzzle.moves, automatic_index),
              next_index: next_index
            })

          {:reply, {:ok, payload}, state}
        end
    end
  end

  defp advance_participant(state, user_id, participant, status) do
    next_index = participant.puzzle_index + 1

    updated = %{
      participant
      | score: participant.score + if(status == :correct, do: 1, else: 0),
        errors: participant.errors + if(status == :incorrect, do: 1, else: 0),
        puzzles_attempted: participant.puzzles_attempted + 1,
        puzzle_index: next_index,
        expected_index: 1,
        complete: next_index >= length(state.puzzles)
    }

    state = put_in(state.participant_states[user_id], updated)
    broadcast(state, "battle_progress", public_progress(state))

    payload =
      base_attempt_payload(state, user_id, status)
      |> Map.merge(%{resolved: status == :correct, puzzle: next_puzzle_payload(state, updated)})

    {:reply, {:ok, payload}, state}
  end

  defp maybe_finish(state) do
    if state.result || DateTime.compare(DateTime.utc_now(), state.battle.ends_at) == :lt,
      do: state,
      else: finish(state)
  end

  defp finish(%{result: nil} = state) do
    Process.cancel_timer(state.timer)
    {:ok, result} = Battles.finish(state.battle.id, state.participant_states)
    state = %{state | result: result}
    broadcast(state, "battle_finished", result)
    state
  end

  defp finish(state), do: state

  defp snapshot_payload(state, user_id) do
    participant = state.participant_states[user_id]

    %{
      battle_id: state.battle.id,
      duration_seconds: state.battle.duration_seconds,
      started_at: state.battle.started_at,
      ends_at: state.battle.ends_at,
      server_now: DateTime.utc_now(:millisecond),
      status: if(state.result, do: :finished, else: battle_status(state.battle)),
      progress: public_progress(state),
      puzzle: if(state.result, do: nil, else: current_puzzle_payload(state, participant)),
      result: state.result
    }
  end

  defp base_attempt_payload(state, user_id, status),
    do: %{
      status: status,
      finished: not is_nil(state.result),
      progress: public_progress(state),
      server_now: DateTime.utc_now(:millisecond),
      ends_at: state.battle.ends_at,
      player_id: user_id
    }

  defp current_puzzle_payload(_state, %{complete: true}), do: nil

  defp current_puzzle_payload(state, participant) do
    state.puzzles
    |> Enum.at(participant.puzzle_index)
    |> Puzzles.public_puzzle(participant.expected_index)
  end

  defp next_puzzle_payload(_state, %{complete: true}), do: nil
  defp next_puzzle_payload(state, participant), do: current_puzzle_payload(state, participant)

  defp public_progress(state) do
    Map.new(state.participant_states, fn {user_id, participant} ->
      user = state.players[user_id]

      {user_id,
       %{
         id: user.id,
         nickname: user.nickname,
         avatar_url: user.avatar_path,
         battle_rating: user.battle_rating,
         score: participant.score,
         errors: participant.errors,
         puzzles_attempted: participant.puzzles_attempted,
         puzzle_index: participant.puzzle_index
       }}
    end)
  end

  defp battle_status(battle) do
    if DateTime.compare(DateTime.utc_now(), battle.started_at) == :lt,
      do: :preparing,
      else: :in_progress
  end

  defp broadcast(state, event, payload),
    do: ChessDuelBackendWeb.Endpoint.broadcast("puzzle_battle:#{state.battle.id}", event, payload)

  defp call_battle(battle_id, message) do
    case Registry.lookup(ChessDuelBackend.PuzzleBattleRegistry, battle_id) do
      [{pid, _}] -> GenServer.call(pid, message)
      [] -> {:error, :battle_not_found}
    end
  end
end
