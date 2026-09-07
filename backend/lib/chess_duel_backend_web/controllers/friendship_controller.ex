defmodule ChessDuelBackendWeb.FriendshipController do
  use ChessDuelBackendWeb, :controller
  alias ChessDuelBackend.Social
  alias ChessDuelBackendWeb.UserJSON

  def index(conn, params) do
    case Social.list(conn.assigns.current_user.id, params["status"]) do
      {:ok, rows} ->
        json(conn, %{friendships: Enum.map(rows, &data(&1, conn.assigns.current_user.id))})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def search(conn, params) do
    users = Social.search(conn.assigns.current_user.id, params["q"])
    json(conn, %{users: Enum.map(users, &public_user/1)})
  end

  def create(conn, params), do: respond(conn, Social.request(conn.assigns.current_user.id, params))

  def accept(conn, %{"id" => id}),
    do: respond(conn, Social.act(conn.assigns.current_user.id, id, :accept))

  def decline(conn, %{"id" => id}),
    do: respond(conn, Social.act(conn.assigns.current_user.id, id, :decline))

  def delete(conn, %{"id" => id}) do
    case Social.act(conn.assigns.current_user.id, id, :delete) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  defp respond(conn, {:ok, f}), do: json(conn, %{friendship: data(f, conn.assigns.current_user.id)})
  defp respond(conn, {:error, reason}), do: error(conn, reason)

  defp data(f, user_id) do
    outgoing = f.requester_id == user_id

    %{
      id: f.id,
      status: f.status,
      direction: if(outgoing, do: "outgoing", else: "incoming"),
      user: public_user(if(outgoing, do: f.addressee, else: f.requester)),
      inserted_at: f.inserted_at,
      updated_at: f.updated_at
    }
  end

  defp public_user(user) do
    # Invisible users remain offline to other people, including friends.
    status = ChessDuelBackend.Games.Lobby.presence_status(user.id)
    status = if status in ~w(online away dnd), do: status, else: "offline"
    UserJSON.public_data(user, %{status: status})
  end

  defp error(conn, reason) do
    {status, message} =
      case reason do
        :already_friends -> {:conflict, "Vocês já são amigos."}
        :already_pending -> {:conflict, "Você já enviou um pedido para este jogador."}
        :not_pending -> {:conflict, "Este pedido já foi respondido."}
        :self_request -> {:unprocessable_entity, "Você não pode adicionar a si mesmo."}
        :not_found -> {:not_found, "Pedido de amizade não encontrado."}
        :user_not_found -> {:not_found, "Jogador não encontrado."}
        :forbidden -> {:forbidden, "Você não pode realizar esta ação."}
        :invalid_status -> {:unprocessable_entity, "Status de amizade inválido."}
        _ -> {:unprocessable_entity, "Informe um jogador válido para enviar o pedido."}
      end

    conn |> put_status(status) |> json(%{error: reason, message: message})
  end
end
