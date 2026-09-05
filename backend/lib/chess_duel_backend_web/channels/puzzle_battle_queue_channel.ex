defmodule ChessDuelBackendWeb.PuzzleBattleQueueChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Puzzles.BattleMatchmaker

  @impl true
  def join("puzzle_battle:queue:" <> user_id, _payload, socket) do
    if socket.assigns[:identity_type] == :user and socket.assigns.user_id == user_id,
      do: {:ok, socket},
      else: {:error, %{reason: "forbidden"}}
  end

  @impl true
  def handle_in("join_queue", %{"duration_seconds" => duration}, socket) do
    case BattleMatchmaker.join(socket.assigns.current_user, duration) do
      {:ok, payload} -> {:reply, {:ok, payload}, assign(socket, :battle_queue, true)}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("leave_queue", _payload, socket) do
    BattleMatchmaker.leave(socket.assigns.user_id)
    {:reply, :ok, assign(socket, :battle_queue, false)}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:battle_queue], do: BattleMatchmaker.leave(socket.assigns.user_id)
    :ok
  end
end
