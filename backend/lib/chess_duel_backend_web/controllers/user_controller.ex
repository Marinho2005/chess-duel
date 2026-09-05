defmodule ChessDuelBackendWeb.UserController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.AvatarStorage
  alias ChessDuelBackendWeb.UserJSON
  alias ChessDuelBackend.Games

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
        stats = Games.public_stats_for_user(user.id)
        recent = Games.list_finished_games_for_user(user.id, page: 1, per_page: 5)

        json(conn, %{
          profile:
            UserJSON.public_data(user, %{
              stats: stats,
              recent_games: recent.games,
              status: Games.player_status(user.id)
            })
        })
    end
  end

  def ranking(conn, params) do
    page = parse_page(params["page"])
    category = parse_category(params["category"])
    ranking = Accounts.list_ranked_users(page, category)

    json(conn, %{
      category: category,
      players:
        ranking.users
        |> Enum.with_index((ranking.page - 1) * ranking.page_size + 1)
        |> Enum.map(fn {user, position} ->
          user
          |> UserJSON.ranking_data(category)
          |> Map.put(:position, position)
          |> Map.put(:status, Games.player_status(user.id))
        end),
      pagination: Map.drop(ranking, [:users])
    })
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

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  defp parse_category(value) when value in ~w(bullet blitz rapid),
    do: String.to_existing_atom(value)

  defp parse_category(_), do: :blitz
end
