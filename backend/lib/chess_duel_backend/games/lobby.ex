defmodule ChessDuelBackend.Games.Lobby do
  use GenServer

  alias ChessDuelBackend.Games.GameServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def connect(user), do: GenServer.call(__MODULE__, {:connect, user})
  def disconnect(user_id), do: GenServer.call(__MODULE__, {:disconnect, user_id})

  def create_challenge(challenger_id, challenged_id),
    do: GenServer.call(__MODULE__, {:create_challenge, challenger_id, challenged_id})

  def accept_challenge(challenge_id, user_id),
    do: GenServer.call(__MODULE__, {:accept_challenge, challenge_id, user_id})

  def decline_challenge(challenge_id, user_id),
    do: GenServer.call(__MODULE__, {:decline_challenge, challenge_id, user_id})

  @impl true
  def init(_state), do: {:ok, %{users: %{}, challenges: %{}}}

  @impl true
  def handle_call({:connect, user}, _from, state) do
    user_data = %{id: user.id, nickname: user.nickname, rating: user.rating}

    users =
      Map.update(state.users, user.id, Map.put(user_data, :connections, 1), fn current ->
        %{current | connections: current.connections + 1}
      end)

    state = %{state | users: users}
    {:reply, snapshot(state), state}
  end

  def handle_call({:disconnect, user_id}, _from, state) do
    {users, disconnected?} = decrement_user(state.users, user_id)

    challenges =
      if disconnected? do
        Map.reject(state.challenges, fn {_id, challenge} ->
          challenge.challenger.id == user_id or challenge.challenged.id == user_id
        end)
      else
        state.challenges
      end

    state = %{state | users: users, challenges: challenges}
    {:reply, snapshot(state), state}
  end

  def handle_call({:create_challenge, user_id, user_id}, _from, state) do
    {:reply, {:error, :cannot_challenge_yourself}, state}
  end

  def handle_call({:create_challenge, challenger_id, challenged_id}, _from, state) do
    with {:ok, challenger} <- fetch_online_user(state, challenger_id),
         {:ok, challenged} <- fetch_online_user(state, challenged_id),
         false <- challenge_exists?(state, challenger_id, challenged_id) do
      challenge = %{
        id: Ecto.UUID.generate(),
        challenger: public_user(challenger),
        challenged: public_user(challenged)
      }

      state = put_in(state.challenges[challenge.id], challenge)
      {:reply, {:ok, snapshot(state)}, state}
    else
      true -> {:reply, {:error, :challenge_already_exists}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:accept_challenge, challenge_id, user_id}, _from, state) do
    case Map.fetch(state.challenges, challenge_id) do
      {:ok, %{challenged: %{id: ^user_id}} = challenge} ->
        game_id = Ecto.UUID.generate()

        case GameServer.reserve_players(game_id, challenge.challenger.id, challenge.challenged.id) do
          {:ok, _game_state} ->
            state = update_in(state.challenges, &Map.delete(&1, challenge_id))

            game = %{
              game_id: game_id,
              white_player: challenge.challenger,
              black_player: challenge.challenged
            }

            {:reply, {:ok, game, snapshot(state)}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:ok, _challenge} ->
        {:reply, {:error, :not_challenged_player}, state}

      :error ->
        {:reply, {:error, :challenge_not_found}, state}
    end
  end

  def handle_call({:decline_challenge, challenge_id, user_id}, _from, state) do
    case Map.fetch(state.challenges, challenge_id) do
      {:ok, %{challenged: %{id: ^user_id}}} ->
        state = update_in(state.challenges, &Map.delete(&1, challenge_id))
        {:reply, {:ok, snapshot(state)}, state}

      {:ok, _challenge} ->
        {:reply, {:error, :not_challenged_player}, state}

      :error ->
        {:reply, {:error, :challenge_not_found}, state}
    end
  end

  defp fetch_online_user(state, user_id) do
    case Map.fetch(state.users, user_id) do
      {:ok, user} -> {:ok, user}
      :error -> {:error, :user_offline}
    end
  end

  defp challenge_exists?(state, challenger_id, challenged_id) do
    Enum.any?(state.challenges, fn {_id, challenge} ->
      challenge.challenger.id == challenger_id and challenge.challenged.id == challenged_id
    end)
  end

  defp decrement_user(users, user_id) do
    case Map.get(users, user_id) do
      nil -> {users, false}
      %{connections: 1} -> {Map.delete(users, user_id), true}
      user -> {Map.put(users, user_id, %{user | connections: user.connections - 1}), false}
    end
  end

  defp snapshot(state) do
    %{
      users: state.users |> Map.values() |> Enum.map(&public_user/1),
      challenges: Map.values(state.challenges)
    }
  end

  defp public_user(user), do: Map.take(user, [:id, :nickname, :rating])
end
