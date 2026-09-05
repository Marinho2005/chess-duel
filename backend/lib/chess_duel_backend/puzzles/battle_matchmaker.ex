defmodule ChessDuelBackend.Puzzles.BattleMatchmaker do
  @moduledoc "Filas em memória, isoladas por duração, para Puzzle Battle."

  use GenServer

  alias ChessDuelBackend.Puzzles.BattleServer

  @interval_ms 1_000
  @base_tolerance 100
  @step 50
  @step_interval_ms 15_000
  @maximum_tolerance 800

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def join(user, duration), do: GenServer.call(__MODULE__, {:join, user, duration})
  def leave(user_id), do: GenServer.call(__MODULE__, {:leave, user_id})
  def match_now, do: GenServer.call(__MODULE__, :match_now)

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @interval_ms)
    schedule(interval)
    {:ok, %{queues: %{180 => [], 300 => []}, interval: interval}}
  end

  @impl true
  def handle_call({:join, user, duration}, _from, state) when duration in [180, 300] do
    queues = remove_from_queues(state.queues, user.id)

    entry = %{
      user: user,
      rating: user.battle_rating,
      joined_at: System.monotonic_time(:millisecond)
    }

    queues = Map.update!(queues, duration, &(&1 ++ [entry]))
    state = %{state | queues: queues} |> match_all()
    waiting = Enum.any?(state.queues[duration], &(&1.user.id == user.id))

    {:reply,
     {:ok, %{duration_seconds: duration, status: if(waiting, do: :waiting, else: :matched)}}, state}
  end

  def handle_call({:join, _user, _duration}, _from, state),
    do: {:reply, {:error, :invalid_duration}, state}

  def handle_call({:leave, user_id}, _from, state) do
    {:reply, :ok, %{state | queues: remove_from_queues(state.queues, user_id)}}
  end

  def handle_call(:match_now, _from, state) do
    state = match_all(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:match, state) do
    state = match_all(state)
    schedule(state.interval)
    {:noreply, state}
  end

  defp match_all(state) do
    now = System.monotonic_time(:millisecond)

    queues =
      Map.new(state.queues, fn {duration, entries} ->
        {duration, match_queue(entries, duration, now)}
      end)

    %{state | queues: queues}
  end

  defp match_queue([], _duration, _now), do: []
  defp match_queue([single], _duration, _now), do: [single]

  defp match_queue([first | rest], duration, now) do
    {before, candidates} = Enum.split_while(rest, &(not compatible?(first, &1, now)))

    case candidates do
      [second | after_second] ->
        case BattleServer.create(first.user, second.user, duration) do
          {:ok, battle_id} ->
            payload = %{battle_id: battle_id, duration_seconds: duration}
            broadcast(first.user.id, "battle_found", payload)
            broadcast(second.user.id, "battle_found", payload)
            match_queue(before ++ after_second, duration, now)

          {:error, _reason} ->
            [first | rest]
        end

      [] ->
        [first | match_queue(rest, duration, now)]
    end
  end

  defp compatible?(first, second, now) do
    abs(first.rating - second.rating) <= max(tolerance(first, now), tolerance(second, now))
  end

  defp tolerance(entry, now) do
    expansion = div(max(now - entry.joined_at, 0), @step_interval_ms) * @step
    min(@base_tolerance + expansion, @maximum_tolerance)
  end

  defp remove_from_queues(queues, user_id) do
    Map.new(queues, fn {duration, entries} ->
      {duration, Enum.reject(entries, &(&1.user.id == user_id))}
    end)
  end

  defp broadcast(user_id, event, payload) do
    ChessDuelBackendWeb.Endpoint.broadcast("puzzle_battle:queue:#{user_id}", event, payload)
  end

  defp schedule(interval), do: Process.send_after(self(), :match, interval)
end
