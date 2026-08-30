defmodule ChessDuelBackendWeb.GuestMatchmakingChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Games.GuestMatchmaker

  @impl true
  def join("guest_matchmaking:" <> guest_id, _payload, socket) do
    if socket.assigns[:identity_type] == :guest and guest_id == socket.assigns.user_id do
      {:ok, assign(socket, :joined_guest_matchmaking, true)}
    else
      {:error, %{reason: "guests_only"}}
    end
  end

  @impl true
  def handle_in("join_queue", _payload, socket) do
    case GuestMatchmaker.join_queue(socket.assigns.current_guest) do
      {:ok, status} -> {:reply, {:ok, %{status: status}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  def handle_in("leave_queue", _payload, socket) do
    :ok = GuestMatchmaker.leave_queue(socket.assigns.user_id)
    {:reply, :ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:joined_guest_matchmaking] do
      GuestMatchmaker.leave_queue(socket.assigns.user_id)
    end

    :ok
  end
end
