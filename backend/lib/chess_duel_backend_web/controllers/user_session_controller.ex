defmodule ChessDuelBackendWeb.UserSessionController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackendWeb.UserJSON

  def create(conn, params) do
    credentials = Map.get(params, "user", params)
    email = Map.get(credentials, "email", "")
    password = Map.get(credentials, "password", "")

    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_email_or_password"})

      user ->
        token = Accounts.generate_user_api_token(user)
        json(conn, %{token: token, user: UserJSON.data(user)})
    end
  end

  def delete(conn, _params) do
    Accounts.delete_user_api_token(conn.assigns.current_user_token)

    ChessDuelBackendWeb.Endpoint.broadcast(
      "users_socket:#{conn.assigns.current_user.id}",
      "disconnect",
      %{}
    )

    send_resp(conn, :no_content, "")
  end
end
