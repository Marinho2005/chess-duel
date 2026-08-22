defmodule ChessDuelBackendWeb.UserSocket do
  use Phoenix.Socket

  alias ChessDuelBackend.Accounts

  channel "games:*", ChessDuelBackendWeb.GamesChannel
  channel "game:*", ChessDuelBackendWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Accounts.get_user_by_api_token(token) do
      {user, _token_inserted_at} ->
        {:ok, socket |> assign(:current_user, user) |> assign(:user_id, user.id)}

      nil ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "users_socket:#{socket.assigns.user_id}"
end
