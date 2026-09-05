defmodule ChessDuelBackendWeb.BroadcastWatchChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Broadcasts.Analysis

  @impl true
  def join("broadcast_watch:" <> game_id, _payload, socket) do
    case ChessDuelBackend.Broadcasts.get_live_game(game_id) do
      {:ok, game} -> {:ok, game, assign(socket, :broadcast_game_id, game_id)}
      :error -> {:error, %{reason: "broadcast_not_found"}}
    end
  end

  @impl true
  def handle_in("evaluate", %{"ply" => ply}, socket) do
    case Analysis.request(socket.assigns.broadcast_game_id, ply) do
      {:ok, analysis} ->
        payload = Map.merge(analysis, %{status: "ready", ply: ply})
        {:reply, {:ok, payload}, socket}

      {:pending, ^ply} ->
        {:reply, {:ok, %{status: "pending", ply: ply}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end
end
