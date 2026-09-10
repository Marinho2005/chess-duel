defmodule ChessDuelBackendWeb.AdminController do
  use ChessDuelBackendWeb, :controller
  alias ChessDuelBackend.Admin
  alias ChessDuelBackendWeb.{AdminJSON, UserJSON}

  plug :private_response

  def dashboard(conn, _), do: json(conn, Admin.dashboard())
  def system(conn, _), do: json(conn, Admin.system())

  def users(conn, params) do
    case Admin.list_users(params) do
      {:ok, result} ->
        json(conn, %{
          users: Enum.map(result.entries, &AdminJSON.user/1),
          pagination: result.pagination
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def user(conn, %{"id" => id}) do
    case Admin.user(id) do
      {:ok, result} ->
        json(conn, %{
          user: AdminJSON.user(result.user),
          game_summary: result.game_summary,
          moderation_actions: Enum.map(result.moderation_actions, &AdminJSON.moderation/1)
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def games(conn, params) do
    case Admin.list_games(params) do
      {:ok, result} ->
        json(conn, %{
          games: Enum.map(result.entries, &AdminJSON.game/1),
          pagination: result.pagination
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def game(conn, %{"id" => id}) do
    case Admin.game(id) do
      {:ok, result} -> json(conn, %{game: AdminJSON.game(result)})
      {:error, reason} -> error(conn, reason)
    end
  end

  def suspend(conn, params), do: moderate(conn, params, :suspend)
  def ban(conn, params), do: moderate(conn, params, :ban)
  def reactivate(conn, params), do: moderate(conn, params, :reactivate)

  defp moderate(conn, %{"id" => id} = params, action) do
    case Admin.moderate(conn.assigns.current_user.id, id, action, params) do
      {:ok, user} -> json(conn, %{user: AdminJSON.user(user)})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp private_response(conn, _), do: put_resp_header(conn, "cache-control", "no-store")

  defp error(conn, %Ecto.Changeset{} = changeset),
    do: conn |> put_status(:unprocessable_entity) |> json(%{errors: UserJSON.errors(changeset)})

  defp error(conn, :not_found), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp error(conn, :forbidden),
    do: conn |> put_status(:forbidden) |> json(%{error: "admin_required"})

  defp error(conn, reason) when reason in [:invalid_transition, :self_moderation],
    do: conn |> put_status(:conflict) |> json(%{error: Atom.to_string(reason)})

  defp error(conn, :invalid_filters),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid_filters"})
end
