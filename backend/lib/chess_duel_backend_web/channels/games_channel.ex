defmodule ChessDuelBackendWeb.GamesChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.{Accounts, Social}
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games.Lobby

  @impl true
  def join("games:lobby", payload, socket) do
    if socket.assigns[:identity_type] == :user do
      state = Lobby.connect(socket.assigns.current_user, Map.get(payload, "status", "online"))
      ChessDuelBackendWeb.Endpoint.broadcast("games:lobby", "lobby_updated", state)
      {:ok, state, assign(socket, :joined_lobby, true)}
    else
      {:error, %{reason: "registered_users_only"}}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:joined_lobby] do
      state = Lobby.disconnect(socket.assigns.user_id)
      broadcast_lobby(state, socket)
    end

    :ok
  end

  @impl true
  def handle_in("set_presence", %{"status" => presence_status}, socket) do
    case Lobby.set_presence(socket.assigns.user_id, presence_status) do
      {:ok, state} ->
        broadcast_lobby(state, socket)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("challenge", %{"user_id" => challenged_id} = payload, socket) do
    time_control_id = Map.get(payload, "time_control", "blitz_3_0")

    case Lobby.create_challenge(socket.assigns.user_id, challenged_id, time_control_id) do
      {:ok, state} ->
        broadcast_lobby(state, socket)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("challenge_friend", %{"user_id" => challenged_id} = payload, socket) do
    time_control_id = Map.get(payload, "time_control", "blitz_3_0")

    with {:ok, challenged_id} <- Ecto.UUID.cast(challenged_id),
         true <- Social.friends?(socket.assigns.user_id, challenged_id),
         %User{} = challenged <- Accounts.get_user(challenged_id),
         {:ok, state} <-
           Lobby.create_direct_challenge(
             socket.assigns.current_user,
             challenged,
             time_control_id
           ) do
      broadcast_lobby(state, socket)

      challenge =
        Enum.find(state.challenges, fn challenge ->
          challenge.challenger.id == socket.assigns.user_id and
            challenge.challenged.id == challenged_id
        end)

      {:reply, {:ok, %{challenge: challenge}}, socket}
    else
      false -> {:reply, {:error, %{reason: "not_friends"}}, socket}
      nil -> {:reply, {:error, %{reason: "user_not_found"}}, socket}
      :error -> {:reply, {:error, %{reason: "user_not_found"}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("challenge_user", %{"user_id" => challenged_id} = payload, socket) do
    time_control_id = Map.get(payload, "time_control", "blitz_3_0")

    with {:ok, challenged_id} <- Ecto.UUID.cast(challenged_id),
         %User{confirmed_at: confirmed_at} = challenged <- Accounts.get_user(challenged_id),
         false <- is_nil(confirmed_at),
         {:ok, state} <-
           Lobby.create_direct_challenge(
             socket.assigns.current_user,
             challenged,
             time_control_id
           ) do
      broadcast_lobby(state, socket)

      challenge =
        Enum.find(state.challenges, fn challenge ->
          challenge.challenger.id == socket.assigns.user_id and
            challenge.challenged.id == challenged_id
        end)

      {:reply, {:ok, %{challenge: challenge}}, socket}
    else
      nil -> {:reply, {:error, %{reason: "user_not_found"}}, socket}
      true -> {:reply, {:error, %{reason: "user_not_found"}}, socket}
      :error -> {:reply, {:error, %{reason: "user_not_found"}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("accept_challenge", %{"challenge_id" => challenge_id}, socket) do
    case Lobby.accept_challenge(challenge_id, socket.assigns.user_id) do
      {:ok, game, state} ->
        broadcast_lobby(state, socket)
        ChessDuelBackendWeb.Endpoint.broadcast("games:lobby", "challenge_accepted", game)
        {:reply, {:ok, game}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("decline_challenge", %{"challenge_id" => challenge_id}, socket) do
    case Lobby.decline_challenge(challenge_id, socket.assigns.user_id) do
      {:ok, state} ->
        broadcast_lobby(state, socket)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("cancel_challenge", %{"challenge_id" => challenge_id}, socket) do
    case Lobby.cancel_challenge(challenge_id, socket.assigns.user_id) do
      {:ok, state} ->
        broadcast_lobby(state, socket)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("cancel_challenges", _payload, socket) do
    {:ok, state} = Lobby.cancel_challenges(socket.assigns.user_id)
    broadcast_lobby(state, socket)
    {:reply, :ok, socket}
  end

  defp broadcast_lobby(state, socket) do
    ChessDuelBackendWeb.Endpoint.broadcast(socket.topic, "lobby_updated", state)
    state
  end
end
