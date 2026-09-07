defmodule ChessDuelBackend.Clubs do
  import Ecto.Query
  alias Ecto.Multi
  alias ChessDuelBackend.Repo
  alias ChessDuelBackend.Clubs.{AvatarStorage, Club, Membership}

  def create(user_id, attrs) do
    club_id = Ecto.UUID.generate()

    Multi.new()
    |> Multi.insert(
      :club,
      Club.changeset(%Club{id: club_id}, Map.put(attrs, "creator_id", user_id))
    )
    |> Multi.insert(:membership, fn %{club: club} ->
      Membership.changeset(%Membership{}, %{
        club_id: club.id,
        user_id: user_id,
        role: "admin",
        status: "active"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{club: club}} -> {:ok, club}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def list(params) do
    page = positive_integer(params["page"], 1)
    per_page = 12
    q = params["q"] |> to_string() |> String.trim()
    query = from(c in Club)

    query =
      if q == "",
        do: query,
        else: where(query, [c], fragment("position(lower(?) in lower(?)) > 0", ^q, c.name))

    total = Repo.aggregate(query, :count)

    clubs =
      Repo.all(
        from c in query,
          left_join: m in Membership,
          on: m.club_id == c.id and m.status == "active",
          group_by: c.id,
          order_by: [desc: c.inserted_at, desc: c.id],
          limit: ^per_page,
          offset: ^((page - 1) * per_page),
          select: {c, count(m.id)}
      )

    %{
      clubs: clubs,
      page: page,
      per_page: per_page,
      total: total,
      total_pages: max(ceil(total / per_page), 1)
    }
  end

  def get(id, viewer_id) do
    with {:ok, id} <- Ecto.UUID.cast(id), %Club{} = club <- Repo.get(Club, id) do
      memberships =
        Repo.all(
          from m in Membership,
            where: m.club_id == ^id and m.status == "active",
            join: u in assoc(m, :user),
            preload: [user: u],
            order_by: [asc: m.role, asc: u.nickname]
        )

      viewer = Repo.one(from m in Membership, where: m.club_id == ^id and m.user_id == ^viewer_id)

      pending =
        if viewer && viewer.role == "admin" && viewer.status == "active" do
          Repo.all(
            from m in Membership,
              where: m.club_id == ^id and m.status == "pending",
              join: u in assoc(m, :user),
              preload: [user: u],
              order_by: [asc: m.inserted_at]
          )
        else
          []
        end

      {:ok, %{club: club, memberships: memberships, viewer: viewer, pending: pending}}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_for_user(user_id) do
    from(m in Membership,
      where: m.user_id == ^user_id and m.status == "active",
      join: c in assoc(m, :club),
      left_join: members in Membership,
      on: members.club_id == c.id and members.status == "active",
      group_by: [c.id, m.role],
      order_by: [asc: c.name],
      select: %{club: c, role: m.role, member_count: count(members.id)}
    )
    |> Repo.all()
  end

  def join(club_id, user_id) do
    with {:ok, club_id} <- Ecto.UUID.cast(club_id), %Club{} = club <- Repo.get(Club, club_id) do
      status = if club.join_policy == "open", do: "active", else: "pending"

      case Repo.get_by(Membership, club_id: club_id, user_id: user_id) do
        nil ->
          Repo.insert(
            Membership.changeset(%Membership{}, %{
              club_id: club_id,
              user_id: user_id,
              role: "member",
              status: status
            })
          )

        %Membership{status: "active"} ->
          {:error, :already_member}

        %Membership{status: "pending"} ->
          {:error, :already_pending}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def update(club_id, actor_id, attrs) do
    with {:ok, club} <- admin_club(club_id, actor_id), do: Repo.update(Club.changeset(club, attrs))
  end

  def save_avatar(club_id, actor_id, upload) do
    with {:ok, club} <- admin_club(club_id, actor_id),
         {:ok, path} <- AvatarStorage.save(upload, club.id) do
      case Repo.update(Club.changeset(club, %{"avatar_path" => path})) do
        {:ok, updated} ->
          AvatarStorage.delete(club.avatar_path)
          {:ok, updated}

        {:error, reason} ->
          AvatarStorage.delete(path)
          {:error, reason}
      end
    end
  end

  def membership_action(club_id, membership_id, actor_id, action) do
    with {:ok, club_id} <- Ecto.UUID.cast(club_id),
         {:ok, membership_id} <- Ecto.UUID.cast(membership_id) do
      Repo.transaction(fn ->
        # A stable lock across the club prevents simultaneous departures from
        # both seeing another admin and leaving the club without administrators.
        memberships =
          Repo.all(
            from m in Membership,
              where: m.club_id == ^club_id,
              order_by: [asc: m.id],
              lock: "FOR UPDATE"
          )

        membership = Enum.find(memberships, &(&1.id == membership_id))
        actor = Enum.find(memberships, &(&1.user_id == actor_id))
        apply_action(membership, actor, memberships, actor_id, action)
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp apply_action(nil, _, _, _, _), do: Repo.rollback(:not_found)

  defp apply_action(m, actor, _, _, action) when action in [:approve, :decline, :promote] do
    unless admin?(actor), do: Repo.rollback(:forbidden)

    case action do
      :approve when m.status == "pending" -> update!(m, %{status: "active"})
      :decline when m.status == "pending" -> Repo.delete!(m)
      :promote when m.status == "active" and m.role == "member" -> update!(m, %{role: "admin"})
      _ -> Repo.rollback(:invalid_membership_state)
    end
  end

  defp apply_action(m, actor, memberships, actor_id, :delete) do
    unless m.user_id == actor_id or admin?(actor), do: Repo.rollback(:forbidden)

    if m.role == "admin" and m.status == "active" and active_admin_count(memberships) <= 1,
      do: Repo.rollback(:last_admin)

    Repo.delete!(m)
  end

  defp admin_club(id, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Club{} = club <- Repo.get(Club, id),
         %Membership{} <-
           Repo.get_by(Membership, club_id: id, user_id: user_id, role: "admin", status: "active") do
      {:ok, club}
    else
      nil -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp admin?(%Membership{role: "admin", status: "active"}), do: true
  defp admin?(_), do: false

  defp active_admin_count(memberships),
    do: Enum.count(memberships, &(&1.role == "admin" and &1.status == "active"))

  defp update!(membership, attrs), do: membership |> Membership.changeset(attrs) |> Repo.update!()

  defp positive_integer(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> fallback
    end
  end

  defp positive_integer(_, fallback), do: fallback
end
