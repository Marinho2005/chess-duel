defmodule ChessDuelBackendWeb.UserSocket do
  use Phoenix.Socket

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.Guest

  channel "games:*", ChessDuelBackendWeb.GamesChannel
  channel "game:*", ChessDuelBackendWeb.GameChannel
  channel "matchmaking:*", ChessDuelBackendWeb.MatchmakingChannel
  channel "guest_matchmaking:*", ChessDuelBackendWeb.GuestMatchmakingChannel
  channel "private_rooms:*", ChessDuelBackendWeb.PrivateRoomChannel
  channel "puzzle_rush:*", ChessDuelBackendWeb.PuzzleRushChannel
  channel "puzzle_battle:queue:*", ChessDuelBackendWeb.PuzzleBattleQueueChannel
  channel "puzzle_battle:*", ChessDuelBackendWeb.PuzzleBattleChannel
  channel "broadcast_watch:*", ChessDuelBackendWeb.BroadcastWatchChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    cond do
      Guest.token?(token) ->
        case Guest.verify(token) do
          {:ok, guest} ->
            {:ok,
             socket
             |> assign(:current_guest, guest)
             |> assign(:user_id, guest.id)
             |> assign(:identity_type, :guest)}

          :error ->
            :error
        end

      true ->
        case Accounts.get_user_by_api_token(token) do
          {user, _token_inserted_at} ->
            {:ok,
             socket
             |> assign(:current_user, user)
             |> assign(:user_id, user.id)
             |> assign(:identity_type, :user)}

          nil ->
            :error
        end
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{identity_type: :guest, user_id: id}}), do: "guests_socket:#{id}"
  def id(socket), do: "users_socket:#{socket.assigns.user_id}"
end
