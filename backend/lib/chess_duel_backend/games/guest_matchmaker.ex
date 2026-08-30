defmodule ChessDuelBackend.Games.GuestMatchmaker do
  @moduledoc "Fila FIFO em memoria, exclusiva para partidas casuais entre convidados."

  use GenServer

  alias ChessDuelBackend.Games.{GameServer, TimeControl}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def join_queue(guest), do: GenServer.call(__MODULE__, {:join_queue, guest})
  def leave_queue(guest_id), do: GenServer.call(__MODULE__, {:leave_queue, guest_id})
  def waiting_guests, do: GenServer.call(__MODULE__, :waiting_guests)

  @impl true
  def init(_state), do: {:ok, %{waiting: []}}

  @impl true
  def handle_call({:join_queue, %{guest: true} = guest}, _from, state) do
    waiting = Enum.reject(state.waiting, &(&1.id == guest.id))

    case waiting do
      [opponent | remaining] ->
        {white, black} = randomize_colors(opponent, guest)
        game_id = Ecto.UUID.generate()
        control = TimeControl.default()

        case GameServer.reserve_guest_players(game_id, white, black, control) do
          {:ok, _game_state} ->
            payload = %{
              game_id: game_id,
              white_player: public_guest(white),
              black_player: public_guest(black),
              time_control: control,
              guest_game: true
            }

            broadcast_match(opponent.id, payload)
            broadcast_match(guest.id, payload)
            {:reply, {:ok, :matched}, %{state | waiting: remaining}}

          {:error, reason} ->
            {:reply, {:error, reason}, %{state | waiting: waiting}}
        end

      [] ->
        {:reply, {:ok, :waiting}, %{state | waiting: [guest]}}
    end
  end

  def handle_call({:join_queue, _identity}, _from, state) do
    {:reply, {:error, :guests_only}, state}
  end

  def handle_call({:leave_queue, guest_id}, _from, state) do
    waiting = Enum.reject(state.waiting, &(&1.id == guest_id))
    {:reply, :ok, %{state | waiting: waiting}}
  end

  def handle_call(:waiting_guests, _from, state) do
    {:reply, Enum.map(state.waiting, &public_guest/1), state}
  end

  defp randomize_colors(first, second) do
    if :rand.uniform(2) == 1, do: {first, second}, else: {second, first}
  end

  defp public_guest(guest) do
    %{id: guest.id, nickname: guest.nickname, rating: nil, avatar_url: nil, guest: true}
  end

  defp broadcast_match(guest_id, payload) do
    ChessDuelBackendWeb.Endpoint.broadcast(
      "guest_matchmaking:#{guest_id}",
      "match_found",
      payload
    )
  end
end
