defmodule ChessDuelBackendWeb.UserConfirmationController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts

  def create(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        json(conn, %{status: "confirmed"})

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_or_expired_confirmation_token"})
    end
  end
end
