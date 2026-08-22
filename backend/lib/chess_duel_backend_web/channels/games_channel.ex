defmodule ChessDuelBackendWeb.GamesChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Games.Lobby

  @impl true
  def join("games:lobby", _payload, socket) do
    state = Lobby.connect(socket.assigns.current_user)
    ChessDuelBackendWeb.Endpoint.broadcast("games:lobby", "lobby_updated", state)
    {:ok, state, assign(socket, :joined_lobby, true)}
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
  def handle_in("challenge", %{"user_id" => challenged_id}, socket) do
    case Lobby.create_challenge(socket.assigns.user_id, challenged_id) do
      {:ok, state} ->
        broadcast_lobby(state, socket)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
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

  defp broadcast_lobby(state, socket) do
    ChessDuelBackendWeb.Endpoint.broadcast(socket.topic, "lobby_updated", state)
    state
  end
end
