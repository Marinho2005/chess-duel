defmodule ChessDuelBackendWeb.ClubController do
  use ChessDuelBackendWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias ChessDuelBackend.Clubs
  alias ChessDuelBackendWeb.UserJSON

  def index(conn, params) do
    result = Clubs.list(params)

    json(conn, %{
      clubs: Enum.map(result.clubs, fn {club, count} -> summary(club, count) end),
      pagination: Map.drop(result, [:clubs])
    })
  end

  def show(conn, %{"id" => id}) do
    case Clubs.get(id, conn.assigns.current_user.id) do
      {:ok, details} -> json(conn, club_details(details))
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, params) do
    attrs = Map.get(params, "club", params)

    case Clubs.create(conn.assigns.current_user.id, attrs) do
      {:ok, club} ->
        with {:ok, club} <- maybe_save_avatar(club, conn.assigns.current_user.id, params["avatar"]) do
          conn |> put_status(:created) |> json(%{club: summary(club, 1)})
        else
          {:error, reason} ->
            # An invalid optional avatar must not leave a half-created club behind.
            ChessDuelBackend.Repo.delete(club)
            error(conn, reason)
        end

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.get(params, "club", Map.drop(params, ["id", "avatar"]))

    with {:ok, club} <- Clubs.update(id, conn.assigns.current_user.id, attrs),
         {:ok, club} <- maybe_save_avatar(club, conn.assigns.current_user.id, params["avatar"]) do
      json(conn, %{club: summary(club, active_count(club.id))})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  def join(conn, %{"id" => id}),
    do: membership_response(conn, Clubs.join(id, conn.assigns.current_user.id))

  def approve(conn, params), do: act(conn, params, :approve)
  def decline(conn, params), do: act(conn, params, :decline)
  def promote(conn, params), do: act(conn, params, :promote)

  def delete_membership(conn, params) do
    case Clubs.membership_action(
           params["id"],
           params["membership_id"],
           conn.assigns.current_user.id,
           :delete
         ) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  defp act(conn, params, action) do
    membership_response(
      conn,
      Clubs.membership_action(
        params["id"],
        params["membership_id"],
        conn.assigns.current_user.id,
        action
      )
    )
  end

  defp membership_response(conn, {:ok, membership}),
    do: json(conn, %{membership: membership_data(membership)})

  defp membership_response(conn, {:error, reason}), do: error(conn, reason)

  defp club_details(%{club: club, memberships: memberships, viewer: viewer, pending: pending}) do
    %{
      club:
        summary(club, length(memberships))
        |> Map.merge(%{
          creator_id: club.creator_id,
          members: Enum.map(memberships, &membership_data/1),
          pending_memberships: Enum.map(pending, &membership_data/1),
          viewer_membership: if(viewer, do: membership_data(viewer), else: nil),
          can_administer: viewer != nil and viewer.role == "admin" and viewer.status == "active"
        })
    }
  end

  defp summary(club, count),
    do: %{
      id: club.id,
      name: club.name,
      description: club.description,
      avatar_url: club.avatar_path,
      join_policy: club.join_policy,
      member_count: count,
      inserted_at: club.inserted_at
    }

  defp membership_data(membership) do
    base = %{
      id: membership.id,
      role: membership.role,
      status: membership.status,
      user_id: membership.user_id
    }

    if Ecto.assoc_loaded?(membership.user),
      do: Map.put(base, :user, public_user(membership.user)),
      else: base
  end

  defp public_user(user),
    do: UserJSON.public_data(user, %{status: ChessDuelBackend.Games.player_status(user.id)})

  defp active_count(club_id),
    do:
      ChessDuelBackend.Repo.aggregate(
        from(m in ChessDuelBackend.Clubs.Membership,
          where: m.club_id == ^club_id and m.status == "active"
        ),
        :count
      )

  defp maybe_save_avatar(club, _user_id, nil), do: {:ok, club}

  defp maybe_save_avatar(club, user_id, %Plug.Upload{} = upload),
    do: Clubs.save_avatar(club.id, user_id, upload)

  defp maybe_save_avatar(_, _, _), do: {:error, :invalid_image}

  defp error(conn, %Ecto.Changeset{} = changeset),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "validation_failed", errors: UserJSON.errors(changeset)})

  defp error(conn, reason) do
    {status, message} =
      case reason do
        :not_found ->
          {:not_found, "Clube ou membro não encontrado."}

        :forbidden ->
          {:forbidden, "Apenas administradores podem realizar esta ação."}

        :already_member ->
          {:conflict, "Você já participa deste clube."}

        :already_pending ->
          {:conflict, "Sua solicitação já está aguardando aprovação."}

        :last_admin ->
          {:conflict, "O único administrador não pode sair ou ser removido."}

        :invalid_membership_state ->
          {:conflict, "Esta ação não é válida para o estado atual do membro."}

        :file_too_large ->
          {:unprocessable_entity, "A imagem deve ter no máximo 2 MB."}

        :invalid_image ->
          {:unprocessable_entity, "Envie uma imagem JPG, PNG ou WebP válida."}

        _ ->
          {:unprocessable_entity, "Não foi possível concluir a operação."}
      end

    conn |> put_status(status) |> json(%{error: reason, message: message})
  end
end
