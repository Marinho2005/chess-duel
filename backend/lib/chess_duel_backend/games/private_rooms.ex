defmodule ChessDuelBackend.Games.PrivateRooms do
  @moduledoc "Salas privadas efemeras para partidas entre identidades do mesmo tipo."

  use GenServer

  alias ChessDuelBackend.Games.{GameServer, TimeControl}

  @default_expiration_ms :timer.minutes(20)
  @code_bytes 6

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def create(identity, identity_type, time_control_id),
    do: GenServer.call(__MODULE__, {:create, identity, identity_type, time_control_id})

  def join(code, identity, identity_type),
    do: GenServer.call(__MODULE__, {:join, normalize_code(code), identity, identity_type})

  def get(code), do: GenServer.call(__MODULE__, {:get, normalize_code(code)})

  @impl true
  def init(opts) do
    expiration_ms = Keyword.get(opts, :expiration_ms, configured_expiration_ms())
    {:ok, %{rooms: %{}, expiration_ms: expiration_ms}}
  end

  @impl true
  def handle_call({:create, identity, identity_type, time_control_id}, _from, state)
      when identity_type in [:user, :guest] do
    with {:ok, time_control} <- TimeControl.fetch(time_control_id) do
      code = unique_code(state.rooms)
      timer_ref = Process.send_after(self(), {:expire, code}, state.expiration_ms)

      room = %{
        code: code,
        creator: identity,
        identity_type: identity_type,
        time_control: time_control,
        status: :waiting,
        timer_ref: timer_ref,
        expires_at: DateTime.add(DateTime.utc_now(), state.expiration_ms, :millisecond)
      }

      {:reply, {:ok, public_room(room)}, put_in(state.rooms[code], room)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create, _identity, _identity_type, _time_control_id}, _from, state),
    do: {:reply, {:error, :invalid_identity}, state}

  def handle_call({:join, code, identity, identity_type}, _from, state) do
    case Map.fetch(state.rooms, code) do
      :error ->
        {:reply, {:error, :room_not_found}, state}

      {:ok, %{status: :full}} ->
        {:reply, {:error, :room_full}, state}

      {:ok, %{creator: %{id: creator_id}} = room} when creator_id == identity.id ->
        {:reply, {:ok, :waiting, public_room(room)}, state}

      {:ok, %{identity_type: expected}} when expected != identity_type ->
        {:reply, {:error, :identity_mismatch}, state}

      {:ok, room} ->
        start_game(room, identity, state)
    end
  end

  def handle_call({:get, code}, _from, state) do
    case Map.fetch(state.rooms, code) do
      {:ok, room} -> {:reply, {:ok, public_room(room)}, state}
      :error -> {:reply, {:error, :room_not_found}, state}
    end
  end

  @impl true
  def handle_info({:expire, code}, state) do
    {:noreply, update_in(state.rooms, &Map.delete(&1, code))}
  end

  defp start_game(room, opponent, state) do
    {white, black} = randomize_colors(room.creator, opponent)
    game_id = Ecto.UUID.generate()

    reservation =
      case room.identity_type do
        :user -> GameServer.reserve_players(game_id, white.id, black.id, room.time_control)
        :guest -> GameServer.reserve_guest_players(game_id, white, black, room.time_control)
      end

    case reservation do
      {:ok, _game_state} ->
        payload = %{
          game_id: game_id,
          code: room.code,
          time_control: room.time_control,
          guest_game: room.identity_type == :guest
        }

        broadcast_match(room.creator.id, payload)
        broadcast_match(opponent.id, payload)
        full_room = %{room | status: :full}
        {:reply, {:ok, :matched, payload}, put_in(state.rooms[room.code], full_room)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp unique_code(rooms) do
    code =
      @code_bytes
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)
      |> String.upcase()

    if Map.has_key?(rooms, code), do: unique_code(rooms), else: code
  end

  defp normalize_code(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  defp normalize_code(_code), do: ""

  defp randomize_colors(first, second) do
    if :rand.uniform(2) == 1, do: {first, second}, else: {second, first}
  end

  defp public_room(room) do
    Map.take(room, [:code, :time_control, :status, :expires_at])
  end

  defp broadcast_match(identity_id, payload) do
    ChessDuelBackendWeb.Endpoint.broadcast(
      "private_rooms:#{identity_id}",
      "match_found",
      payload
    )
  end

  defp configured_expiration_ms do
    Application.get_env(
      :chess_duel_backend,
      :private_room_expiration_ms,
      @default_expiration_ms
    )
  end
end
