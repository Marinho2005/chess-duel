defmodule ChessDuelBackend.Games.Lobby do
  use GenServer

  alias ChessDuelBackend.Games.{GameServer, TimeControl}
  alias ChessDuelBackend.Accounts.User

  @presence_statuses ~w(online away dnd invisible)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def connect(user, presence_status \\ "online"),
    do: GenServer.call(__MODULE__, {:connect, user, presence_status})

  def disconnect(user_id), do: GenServer.call(__MODULE__, {:disconnect, user_id})

  def set_presence(user_id, presence_status),
    do: GenServer.call(__MODULE__, {:set_presence, user_id, presence_status})

  def presence_status(user_id), do: GenServer.call(__MODULE__, {:presence_status, user_id})

  def create_challenge(challenger_id, challenged_id, time_control_id \\ TimeControl.default().id),
    do:
      GenServer.call(
        __MODULE__,
        {:create_challenge, challenger_id, challenged_id, time_control_id}
      )

  def accept_challenge(challenge_id, user_id),
    do: GenServer.call(__MODULE__, {:accept_challenge, challenge_id, user_id})

  def decline_challenge(challenge_id, user_id),
    do: GenServer.call(__MODULE__, {:decline_challenge, challenge_id, user_id})

  @impl true
  def init(_state), do: {:ok, %{users: %{}, challenges: %{}}}

  @impl true
  def handle_call({:connect, user, requested_presence}, _from, state) do
    presence_status = normalize_presence(requested_presence)

    user_data = %{
      id: user.id,
      nickname: user.nickname,
      rating: user.blitz_rating,
      ratings: User.ratings(user),
      avatar_url: user.avatar_path,
      status: presence_status
    }

    users =
      Map.update(state.users, user.id, Map.put(user_data, :connections, 1), fn current ->
        %{current | connections: current.connections + 1, status: presence_status}
      end)

    state = %{state | users: users}
    {:reply, snapshot(state), state}
  end

  def handle_call({:set_presence, user_id, presence_status}, _from, state)
      when presence_status in @presence_statuses do
    case Map.fetch(state.users, user_id) do
      {:ok, user} ->
        state = put_in(state.users[user_id], %{user | status: presence_status})
        {:reply, {:ok, snapshot(state)}, state}

      :error ->
        {:reply, {:error, :user_offline}, state}
    end
  end

  def handle_call({:set_presence, _user_id, _presence_status}, _from, state),
    do: {:reply, {:error, :invalid_presence}, state}

  def handle_call({:presence_status, user_id}, _from, state) do
    status = state.users |> Map.get(user_id, %{status: "offline"}) |> Map.fetch!(:status)
    {:reply, if(status == "invisible", do: "offline", else: status), state}
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

  def handle_call({:create_challenge, user_id, user_id, _time_control_id}, _from, state) do
    {:reply, {:error, :cannot_challenge_yourself}, state}
  end

  def handle_call(
        {:create_challenge, challenger_id, challenged_id, time_control_id},
        _from,
        state
      ) do
    with {:ok, challenger} <- fetch_online_user(state, challenger_id),
         {:ok, challenged} <- fetch_challengeable_user(state, challenged_id),
         {:ok, time_control} <- TimeControl.fetch(time_control_id),
         false <- challenge_exists?(state, challenger_id, challenged_id) do
      challenge = %{
        id: Ecto.UUID.generate(),
        challenger: public_user(challenger),
        challenged: public_user(challenged),
        time_control: time_control
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

        case GameServer.reserve_players(
               game_id,
               challenge.challenger.id,
               challenge.challenged.id,
               challenge.time_control
             ) do
          {:ok, _game_state} ->
            state = update_in(state.challenges, &Map.delete(&1, challenge_id))

            game = %{
              game_id: game_id,
              white_player: challenge.challenger,
              black_player: challenge.challenged,
              time_control: challenge.time_control
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

  defp fetch_challengeable_user(state, user_id) do
    with {:ok, user} <- fetch_online_user(state, user_id),
         true <- user.status in ["online", "away"] do
      {:ok, user}
    else
      false -> {:error, :user_unavailable}
      error -> error
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
      users:
        state.users
        |> Map.values()
        |> Enum.reject(&(&1.status == "invisible"))
        |> Enum.map(&public_user/1),
      challenges: Map.values(state.challenges)
    }
  end

  defp public_user(user),
    do: Map.take(user, [:id, :nickname, :rating, :avatar_url, :status])

  defp normalize_presence(status) when status in @presence_statuses, do: status
  defp normalize_presence(_status), do: "online"
end
