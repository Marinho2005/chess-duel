defmodule ChessDuelBackendWeb.UserController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.AvatarStorage
  alias ChessDuelBackendWeb.UserJSON

  def me(conn, _params) do
    json(conn, %{user: UserJSON.data(conn.assigns.current_user)})
  end

  def show(conn, %{"nickname" => nickname}) do
    case Accounts.get_user_by_nickname(nickname) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "profile_not_found"})

      user ->
        json(conn, %{profile: UserJSON.public_data(user)})
    end
  end

  def update(conn, %{"user" => params}) do
    case Accounts.update_user_profile(conn.assigns.current_user, params) do
      {:ok, user} ->
        json(conn, %{user: UserJSON.data(user)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: UserJSON.errors(changeset)})
    end
  end

  def update_avatar(conn, %{"avatar" => %Plug.Upload{} = upload}) do
    user = conn.assigns.current_user

    case AvatarStorage.save(upload, user.id) do
      {:ok, avatar_path} ->
        case Accounts.update_user_avatar(user, avatar_path) do
          {:ok, updated_user} ->
            AvatarStorage.delete(user.avatar_path)
            json(conn, %{user: UserJSON.data(updated_user)})

          {:error, reason} ->
            AvatarStorage.delete(avatar_path)
            avatar_error(conn, reason)
        end

      {:error, reason} ->
        avatar_error(conn, reason)
    end
  end

  def update_avatar(conn, _params), do: avatar_error(conn, :invalid_image)

  defp avatar_error(conn, reason) do
    message =
      case reason do
        :file_too_large -> "avatar_too_large"
        :invalid_image -> "invalid_avatar_format"
        _ -> "avatar_upload_failed"
      end

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: message})
  end
end
