defmodule ChessDuelBackend.Social do
  import Ecto.Query
  alias ChessDuelBackend.{Accounts, Repo}
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Social.Friendship

  def list(user_id, status) when status in [nil, "pending", "accepted", "declined"] do
    query =
      from f in Friendship,
        where: f.requester_id == ^user_id or f.addressee_id == ^user_id,
        order_by: [desc: f.updated_at, desc: f.id],
        preload: [:requester, :addressee]

    query = if status, do: where(query, [f], f.status == ^status), else: query
    {:ok, Repo.all(query)}
  end

  def list(_, _), do: {:error, :invalid_status}

  def public_friends(user_id) do
    ids =
      from(f in Friendship,
        where:
          f.status == "accepted" and (f.requester_id == ^user_id or f.addressee_id == ^user_id),
        select: {f.requester_id, f.addressee_id}
      )
      |> Repo.all()
      |> Enum.map(fn {requester_id, addressee_id} ->
        if requester_id == user_id, do: addressee_id, else: requester_id
      end)

    Repo.all(from(u in User, where: u.id in ^ids, order_by: [asc: u.nickname]))
  end

  def friends?(first_user_id, second_user_id) do
    Repo.exists?(
      from f in Friendship,
        where: f.status == "accepted",
        where:
          (f.requester_id == ^first_user_id and f.addressee_id == ^second_user_id) or
            (f.requester_id == ^second_user_id and f.addressee_id == ^first_user_id)
    )
  end

  def search(user_id, q) when is_binary(q) do
    term = String.trim(q)

    if String.length(term) in 2..32 do
      # position() treats %, _ and backslashes literally, unlike an ILIKE pattern.
      Repo.all(
        from u in User,
          where: u.id != ^user_id and not is_nil(u.confirmed_at),
          where: fragment("position(lower(?) in lower(?)) > 0", ^term, u.nickname),
          order_by: [asc: u.nickname, asc: u.id],
          limit: 20
      )
    else
      []
    end
  end

  def search(_, _), do: []

  def request(user_id, params) do
    with {:ok, user} <- recipient(params),
         false <- user.id == user_id do
      Repo.transaction(fn ->
        # Lock the same user first in either direction, including when no pair exists yet.
        # This serializes simultaneous requests without locking unrelated users globally.
        lock_id = min(user_id, user.id)
        Repo.one!(from u in User, where: u.id == ^lock_id, lock: "FOR UPDATE")

        pair =
          Repo.one(
            from f in Friendship,
              where:
                (f.requester_id == ^user_id and f.addressee_id == ^user.id) or
                  (f.requester_id == ^user.id and f.addressee_id == ^user_id),
              lock: "FOR UPDATE"
          )

        case pair do
          %Friendship{status: "accepted"} ->
            Repo.rollback(:already_friends)

          %Friendship{status: "pending", requester_id: ^user_id} ->
            Repo.rollback(:already_pending)

          %Friendship{status: "pending"} = f ->
            # Mutual requests express consent from both users: accept automatically.
            save(f, %{status: "accepted"})

          f ->
            # A declined pair may receive a fresh request, reusing its unique row.
            save(f || %Friendship{}, %{
              requester_id: user_id,
              addressee_id: user.id,
              status: "pending"
            })
        end
      end)
    else
      true -> {:error, :self_request}
      error -> error
    end
  end

  def act(user_id, id, action) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.transaction(fn ->
          f = Repo.one(from f in Friendship, where: f.id == ^id, lock: "FOR UPDATE")

          cond do
            is_nil(f) ->
              Repo.rollback(:not_found)

            user_id not in [f.requester_id, f.addressee_id] ->
              Repo.rollback(:not_found)

            action in [:accept, :decline] and f.addressee_id != user_id ->
              Repo.rollback(:forbidden)

            action in [:accept, :decline] and f.status != "pending" ->
              Repo.rollback(:not_pending)

            action == :accept ->
              save(f, %{status: "accepted"})

            action == :decline ->
              save(f, %{status: "declined"})

            action == :delete and
                (f.status == "accepted" or (f.status == "pending" and f.requester_id == user_id)) ->
              Repo.delete!(f)

            true ->
              Repo.rollback(:forbidden)
          end
        end)

      :error ->
        {:error, :not_found}
    end
  end

  defp recipient(%{"user_id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> confirmed(Repo.get(User, id))
      :error -> {:error, :user_not_found}
    end
  end

  defp recipient(%{"username" => name}) when is_binary(name),
    do: confirmed(Accounts.get_user_by_nickname(String.trim(name)))

  defp recipient(_), do: {:error, :invalid_recipient}
  defp confirmed(%User{confirmed_at: date} = user) when not is_nil(date), do: {:ok, user}
  defp confirmed(_), do: {:error, :user_not_found}

  defp save(f, attrs) do
    case Repo.insert_or_update(Friendship.changeset(f, attrs)) do
      {:ok, f} -> Repo.preload(f, [:requester, :addressee], force: true)
      {:error, _} -> Repo.rollback(:invalid_friendship)
    end
  end
end
