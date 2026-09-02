defmodule ChessDuelBackend.Puzzles.RushServer do
  use GenServer
  alias ChessDuelBackend.Puzzles

  @result_retention_ms 300_000
  @maximum_errors 3
  @base_rating 800
  @rating_step 75
  @maximum_rating 2400

  def child_spec(opts),
    do: %{
      id: {__MODULE__, opts[:session_id]},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }

  def start(user_id, duration_seconds) when duration_seconds in [180, 300] do
    session_id = Ecto.UUID.generate()

    spec =
      {__MODULE__, user_id: user_id, duration_seconds: duration_seconds, session_id: session_id}

    case DynamicSupervisor.start_child(ChessDuelBackend.PuzzleRushSupervisor, spec) do
      {:ok, pid} -> GenServer.call(pid, {:snapshot, user_id})
      {:error, reason} -> {:error, reason}
    end
  end

  def snapshot(session_id, user_id), do: call_session(session_id, {:snapshot, user_id})

  def attempt(session_id, user_id, index, move),
    do: call_session(session_id, {:attempt, user_id, index, move})

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {ChessDuelBackend.PuzzleRushRegistry, opts[:session_id]}}
    )
  end

  @impl true
  def init(opts) do
    case select_for_score(0, []) do
      nil ->
        {:stop, :no_puzzles}

      puzzle ->
        duration_ms = opts[:duration_seconds] * 1_000
        preparation_ms = Application.get_env(:chess_duel_backend, :puzzle_rush_countdown_ms, 3_000)
        created_at = DateTime.utc_now(:millisecond)
        started_at = DateTime.add(created_at, preparation_ms, :millisecond)
        timer = Process.send_after(self(), :expire, duration_ms + preparation_ms)

        {:ok,
         %{
           session_id: opts[:session_id],
           user_id: opts[:user_id],
           duration_seconds: opts[:duration_seconds],
           started_at: started_at,
           ends_at: DateTime.add(started_at, duration_ms, :millisecond),
           starts_at_ms: System.monotonic_time(:millisecond) + preparation_ms,
           deadline_ms: System.monotonic_time(:millisecond) + preparation_ms + duration_ms,
           timer: timer,
           puzzle: puzzle,
           expected_index: 1,
           score: 0,
           errors: 0,
           seen_ids: MapSet.new([puzzle.id]),
           finished_at: nil
         }}
    end
  end

  @impl true
  def handle_call({:snapshot, user_id}, _from, state) do
    cond do
      user_id != state.user_id -> {:reply, {:error, :forbidden}, state}
      state.finished_at -> {:reply, {:ok, result_payload(state)}, state}
      remaining_ms(state) <= 0 -> reply_finished(state)
      true -> {:reply, {:ok, snapshot_payload(state)}, state}
    end
  end

  def handle_call({:attempt, user_id, index, move}, _from, state) do
    cond do
      user_id != state.user_id ->
        {:reply, {:error, :forbidden}, state}

      state.finished_at ->
        {:reply, {:ok, result_payload(state)}, state}

      System.monotonic_time(:millisecond) < state.starts_at_ms ->
        {:reply, {:error, :not_started}, state}

      remaining_ms(state) <= 0 ->
        reply_finished(state)

      index != state.expected_index ->
        {:reply, {:error, {:unexpected_index, state.expected_index}}, state}

      Enum.at(state.puzzle.moves, index) != move ->
        handle_incorrect(state)

      index == length(state.puzzle.moves) - 1 ->
        advance_puzzle(state, state.score + 1, state.errors, :correct)

      true ->
        advance_solution(state, index)
    end
  end

  @impl true
  def handle_info(:expire, state) do
    state = finish(state)
    Process.send_after(self(), :stop, @result_retention_ms)
    {:noreply, state}
  end

  def handle_info(:stop, state), do: {:stop, :normal, state}

  defp advance_solution(state, index) do
    automatic_index = index + 1
    next_index = index + 2

    if next_index >= length(state.puzzle.moves) do
      advance_puzzle(state, state.score + 1, state.errors, :correct)
    else
      next_state = %{state | expected_index: next_index}

      payload =
        base_payload(next_state)
        |> Map.merge(%{
          status: :correct,
          resolved: false,
          finished: false,
          automatic_move: Enum.at(state.puzzle.moves, automatic_index),
          next_index: next_index
        })

      {:reply, {:ok, payload}, next_state}
    end
  end

  defp handle_incorrect(state) do
    errors = state.errors + 1

    if errors >= @maximum_errors do
      state = finish(%{state | errors: errors})
      {:reply, {:ok, Map.put(result_payload(state), :status, :incorrect)}, state}
    else
      advance_puzzle(state, state.score, errors, :incorrect)
    end
  end

  defp advance_puzzle(state, score, errors, status) do
    case select_for_score(score, MapSet.to_list(state.seen_ids)) do
      nil ->
        state = finish(%{state | score: score, errors: errors})
        {:reply, {:ok, result_payload(state)}, state}

      puzzle ->
        next_state = %{
          state
          | puzzle: puzzle,
            expected_index: 1,
            score: score,
            errors: errors,
            seen_ids: MapSet.put(state.seen_ids, puzzle.id)
        }

        payload =
          base_payload(next_state)
          |> Map.merge(%{
            status: status,
            resolved: status == :correct,
            finished: false,
            puzzle: Puzzles.public_puzzle(puzzle)
          })

        {:reply, {:ok, payload}, next_state}
    end
  end

  defp finish(%{finished_at: nil} = state) do
    Process.cancel_timer(state.timer)
    finished_at = DateTime.utc_now(:millisecond)

    {:ok, _} =
      Puzzles.create_rush_score(%{
        session_id: state.session_id,
        user_id: state.user_id,
        score: state.score,
        errors: state.errors,
        duration_seconds: state.duration_seconds,
        started_at: state.started_at,
        finished_at: finished_at
      })

    %{state | finished_at: finished_at}
  end

  defp finish(state), do: state

  defp reply_finished(state) do
    state = finish(state)
    {:reply, {:ok, result_payload(state)}, state}
  end

  defp snapshot_payload(state),
    do:
      base_payload(state)
      |> Map.merge(%{
        finished: false,
        puzzle: Puzzles.public_puzzle(state.puzzle, state.expected_index)
      })

  defp result_payload(state),
    do:
      base_payload(state)
      |> Map.merge(%{
        finished: true,
        finished_at: state.finished_at,
        remaining_ms: 0
      })

  defp base_payload(state),
    do: %{
      session_id: state.session_id,
      duration_seconds: state.duration_seconds,
      started_at: state.started_at,
      ends_at: state.ends_at,
      server_now: DateTime.utc_now(:millisecond),
      preparation_remaining_ms: preparation_remaining_ms(state),
      remaining_ms: remaining_ms(state),
      score: state.score,
      errors: state.errors,
      maximum_errors: @maximum_errors
    }

  defp select_for_score(score, excluded_ids) do
    target = min(@base_rating + score * @rating_step, @maximum_rating)
    Puzzles.select_puzzle(target, excluded_ids)
  end

  defp preparation_remaining_ms(state),
    do: max(state.starts_at_ms - System.monotonic_time(:millisecond), 0)

  defp remaining_ms(state) do
    duration_ms = state.duration_seconds * 1_000
    min(max(state.deadline_ms - System.monotonic_time(:millisecond), 0), duration_ms)
  end

  defp call_session(session_id, message) do
    case Registry.lookup(ChessDuelBackend.PuzzleRushRegistry, session_id) do
      [{pid, _}] -> GenServer.call(pid, message)
      [] -> {:error, :session_not_found}
    end
  end
end
