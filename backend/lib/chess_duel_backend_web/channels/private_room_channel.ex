defmodule ChessDuelBackendWeb.PrivateRoomChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Games.PrivateRooms

  @impl true
  def join("private_rooms:" <> identity_id, _payload, socket) do
    if identity_id == socket.assigns.user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("create_room", %{"time_control" => time_control_id}, socket) do
    case PrivateRooms.create(identity(socket), socket.assigns.identity_type, time_control_id) do
      {:ok, room} -> {:reply, {:ok, room}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: format_reason(reason)}}, socket}
    end
  end

  def handle_in("create_room", _payload, socket),
    do: {:reply, {:error, %{reason: "time_control_required"}}, socket}

  def handle_in("join_room", %{"code" => code}, socket) do
    case PrivateRooms.join(code, identity(socket), socket.assigns.identity_type) do
      {:ok, :waiting, room} -> {:reply, {:ok, Map.put(room, :state, :waiting)}, socket}
      {:ok, :matched, game} -> {:reply, {:ok, Map.put(game, :state, :matched)}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: format_reason(reason)}}, socket}
    end
  end

  def handle_in("join_room", _payload, socket),
    do: {:reply, {:error, %{reason: "room_not_found"}}, socket}

  defp identity(%{assigns: %{identity_type: :guest, current_guest: guest}}), do: guest
  defp identity(%{assigns: %{current_user: user}}), do: user

  defp format_reason(reason)
       when reason in [
              :room_not_found,
              :room_full,
              :identity_mismatch,
              :invalid_time_control
            ],
       do: Atom.to_string(reason)

  defp format_reason(_reason), do: "room_unavailable"
end
