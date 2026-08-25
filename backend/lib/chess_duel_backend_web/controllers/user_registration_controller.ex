defmodule ChessDuelBackendWeb.UserRegistrationController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackendWeb.UserJSON

  def create(conn, params) do
    attrs = Map.get(params, "user", params)

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        frontend_url = Application.fetch_env!(:chess_duel_backend, :frontend_url)

        {:ok, _email} =
          Accounts.deliver_user_confirmation_instructions(user, fn token ->
            "#{frontend_url}/auth/confirm/#{token}"
          end)

        conn
        |> put_status(:created)
        |> json(%{
          status: "pending_confirmation",
          message: "Verifique seu email para confirmar sua conta antes de fazer login."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: UserJSON.errors(changeset)})
    end
  end
end
