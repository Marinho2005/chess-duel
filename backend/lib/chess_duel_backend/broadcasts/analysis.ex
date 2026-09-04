defmodule ChessDuelBackend.Broadcasts.Analysis do
  @moduledoc "Fila efêmera e cache de avaliações Stockfish para broadcasts ao vivo."

  use GenServer

  require Logger

  alias ChessDuelBackend.Broadcasts
  alias ChessDuelBackend.GameAnalysis.Stockfish

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def request(game_id, ply, server \\ __MODULE__),
    do: GenServer.call(server, {:request, game_id, ply})

  @impl true
  def init(opts) do
    stockfish_config = Application.get_env(:chess_duel_backend, :stockfish, [])
    depth = Keyword.get(opts, :depth, Keyword.get(stockfish_config, :broadcast_depth, 10))

    {:ok,
     %{
       active: nil,
       cache: %{},
       pending: MapSet.new(),
       queue: :queue.new(),
       game_provider: Keyword.get(opts, :game_provider, &Broadcasts.get_live_game/1),
       evaluator:
         Keyword.get(opts, :evaluator, fn moves -> Stockfish.evaluate(moves, depth: depth) end)
     }}
  end

  @impl true
  def handle_call({:request, game_id, ply}, _from, state) do
    with {:ok, game} <- state.game_provider.(game_id),
         true <- is_integer(ply) and ply >= 0 and ply <= length(game.moves) do
      key = {game_id, ply}

      cond do
        evaluation = state.cache[key] ->
          {:reply, {:ok, evaluation}, state}

        MapSet.member?(state.pending, key) ->
          {:reply, {:pending, ply}, state}

        true ->
          item = %{key: key, game_id: game_id, ply: ply, moves: Enum.take(game.moves, ply)}

          state =
            state
            |> Map.update!(:pending, &MapSet.put(&1, key))
            |> enqueue_or_start(item)

          {:reply, {:pending, ply}, state}
      end
    else
      :error -> {:reply, {:error, :broadcast_not_found}, state}
      false -> {:reply, {:error, :invalid_ply}, state}
    end
  end

  @impl true
  def handle_info({ref, result}, %{active: %{ref: ref} = active} = state) do
    Process.demonitor(ref, [:flush])

    state =
      state
      |> finish(active, result)
      |> start_next()

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{active: %{ref: ref} = active} = state) do
    Logger.warning("Broadcast Stockfish task failed: #{inspect(reason)}")

    state =
      state
      |> Map.put(:active, nil)
      |> Map.update!(:pending, &MapSet.delete(&1, active.key))
      |> start_next()

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp enqueue_or_start(%{active: nil} = state, item), do: start_task(state, item)

  defp enqueue_or_start(state, item),
    do: Map.update!(state, :queue, &:queue.in(item, &1))

  defp start_task(state, item) do
    task =
      Task.Supervisor.async_nolink(ChessDuelBackend.BroadcastAnalysisSupervisor, fn ->
        state.evaluator.(item.moves)
      end)

    %{state | active: Map.put(item, :ref, task.ref)}
  end

  defp finish(state, active, {:ok, analysis}) do
    ChessDuelBackendWeb.Endpoint.broadcast(
      "broadcast_watch:#{active.game_id}",
      "broadcast_evaluation",
      Map.put(analysis, :ply, active.ply)
    )

    state
    |> Map.put(:active, nil)
    |> Map.update!(:cache, &Map.put(&1, active.key, analysis))
    |> Map.update!(:pending, &MapSet.delete(&1, active.key))
  end

  defp finish(state, active, {:error, reason}) do
    Logger.warning(
      "Could not evaluate broadcast #{active.game_id} ply #{active.ply}: #{inspect(reason)}"
    )

    state
    |> Map.put(:active, nil)
    |> Map.update!(:pending, &MapSet.delete(&1, active.key))
  end

  defp start_next(state) do
    case :queue.out(state.queue) do
      {{:value, item}, queue} -> state |> Map.put(:queue, queue) |> start_task(item)
      {:empty, _queue} -> state
    end
  end
end
