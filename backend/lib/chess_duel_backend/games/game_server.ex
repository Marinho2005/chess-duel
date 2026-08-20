defmodule ChessDuelBackend.Games.GameServer do
  use GenServer, restart: :transient

  alias ChessDuelBackend.{GameRegistry, GameSupervisor}
  alias ChessDuelBackend.ChessValidator

  @initial_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  # Pode ser sobrescrito com config :chess_duel_backend, :game_clock_initial_ms
  # para testes manuais curtos. O padrao permanece 3 minutos por jogador.
  @default_initial_time_ms 180_000

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via_tuple(game_id))
  end

  def child_spec(game_id) do
    %{
      id: {__MODULE__, game_id},
      start: {__MODULE__, :start_link, [game_id]},
      restart: :transient
    }
  end

  def start_or_get(game_id) when is_binary(game_id) do
    case Registry.lookup(GameRegistry, game_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(GameSupervisor, {__MODULE__, game_id}) do
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

  def get_state(game_id) do
    with {:ok, pid} <- start_or_get(game_id) do
      GenServer.call(pid, :get_state)
    end
  end

  @impl true
  def init(game_id) do
    initial_time_ms =
      Application.get_env(
        :chess_duel_backend,
        :game_clock_initial_ms,
        @default_initial_time_ms
      )

    {:ok,
     %{
       game_id: game_id,
       moves: [],
       current_turn: "white",
       fen: @initial_fen,
       status: "in_progress",
       is_check: false,
       is_checkmate: false,
       is_stalemate: false,
       is_draw: false,
       white_time_remaining_ms: initial_time_ms,
       black_time_remaining_ms: initial_time_ms,
       turn_started_at: nil,
       clock_timer_ref: nil
     }}
  end

  @impl true
  def handle_call(
        {:make_move, _from, _to, _player, _promotion},
        _caller,
        %{status: "finished"} = state
      ) do
    {:reply, {:error, :game_finished}, state}
  end

  def handle_call({:make_move, from, to, player, promotion}, _from, state) do
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
              captured: result.captured
            }

            next_turn = opposite_color(state.current_turn)
            finished = result.is_checkmate or result.is_stalemate or result.is_draw

            cancel_clock_timer(clock_state.clock_timer_ref)

            new_state =
              clock_state
              |> Map.merge(%{
                moves: state.moves ++ [move],
                current_turn: next_turn,
                fen: result.new_fen,
                status: if(finished, do: "finished", else: "in_progress"),
                is_check: result.is_check,
                is_checkmate: result.is_checkmate,
                is_stalemate: result.is_stalemate,
                is_draw: result.is_draw,
                turn_started_at: now,
                clock_timer_ref: nil
              })
              |> schedule_current_clock_unless_finished()

            {:reply, {:ok, snapshot_clock(new_state, now)}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, snapshot_clock(state)}, state}
  end

  @impl true
  def handle_info(:time_expired, %{status: "finished"} = state), do: {:noreply, state}

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

    topic = "game:#{state.game_id}"

    Phoenix.PubSub.broadcast(
      ChessDuelBackend.PubSub,
      topic,
      %Phoenix.Socket.Broadcast{
        topic: topic,
        event: "game_over",
        payload: %{reason: "timeout", winner: winner}
      }
    )

    %{state | status: "finished", clock_timer_ref: nil, turn_started_at: nil}
  end

  defp time_key("white"), do: :white_time_remaining_ms
  defp time_key("black"), do: :black_time_remaining_ms

  defp opposite_color("white"), do: "black"
  defp opposite_color("black"), do: "white"

  defp via_tuple(game_id), do: {:via, Registry, {GameRegistry, game_id}}
end
