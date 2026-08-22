defmodule ChessDuelBackendWeb.UserRegistrationController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackendWeb.UserJSON

  def create(conn, params) do
    attrs = Map.get(params, "user", params)

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        token = Accounts.generate_user_api_token(user)

        conn
        |> put_status(:created)
        |> json(%{token: token, user: UserJSON.data(user)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: UserJSON.errors(changeset)})
    end
  end
end
