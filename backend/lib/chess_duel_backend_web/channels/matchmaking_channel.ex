defmodule ChessDuelBackendWeb.MatchmakingChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Games.Matchmaker

  @impl true
  def join("matchmaking:" <> user_id, _payload, socket) do
    if user_id == socket.assigns.user_id do
      {:ok, assign(socket, :joined_matchmaking, true)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("join_queue", %{"time_control" => time_control_id}, socket) do
    case Matchmaker.join_queue(socket.assigns.current_user, time_control_id) do
      {:ok, queue} -> {:reply, {:ok, queue}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: format_reason(reason)}}, socket}
    end
  end

  def handle_in("join_queue", _payload, socket) do
    {:reply, {:error, %{reason: "time_control_required"}}, socket}
  end

  def handle_in("leave_queue", _payload, socket) do
    case Matchmaker.leave_queue(socket.assigns.user_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: format_reason(reason)}}, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:joined_matchmaking] do
      Matchmaker.leave_queue(socket.assigns.user_id)
    end

    :ok
  end

  defp format_reason({:valkey_error, _reason}), do: "queue_unavailable"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(_reason), do: "queue_unavailable"
end
