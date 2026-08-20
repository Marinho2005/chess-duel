defmodule ChessDuelBackend.Games.GameServer do
  use GenServer, restart: :transient

  alias ChessDuelBackend.{GameRegistry, GameSupervisor}
  alias ChessDuelBackend.ChessValidator

  @initial_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

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
       is_draw: false
     }}
  end

  @impl true
  def handle_call({:make_move, from, to, player, promotion}, _from, state) do
    case ChessValidator.validate_move(state.fen, from, to, promotion) do
      {:ok, result} ->
        move = %{
          from: from,
          to: to,
          player: player,
          promotion: promotion,
          captured: result.captured
        }

        next_turn = if state.current_turn == "white", do: "black", else: "white"
        finished = result.is_checkmate or result.is_stalemate or result.is_draw

        new_state =
          state
          |> Map.merge(%{
            moves: state.moves ++ [move],
            current_turn: next_turn,
            fen: result.new_fen,
            status: if(finished, do: "finished", else: "in_progress"),
            is_check: result.is_check,
            is_checkmate: result.is_checkmate,
            is_stalemate: result.is_stalemate,
            is_draw: result.is_draw
          })

        {:reply, {:ok, new_state}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_state, _from, state), do: {:reply, {:ok, state}, state}

  defp via_tuple(game_id), do: {:via, Registry, {GameRegistry, game_id}}
end
