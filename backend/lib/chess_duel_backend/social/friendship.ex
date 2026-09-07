defmodule ChessDuelBackend.Social.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "friendships" do
    belongs_to :requester, ChessDuelBackend.Accounts.User
    belongs_to :addressee, ChessDuelBackend.Accounts.User
    field :status, :string, default: "pending"
    timestamps()
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:requester_id, :addressee_id, :status])
    |> validate_required([:requester_id, :addressee_id, :status])
    |> validate_inclusion(:status, ~w(pending accepted declined))
    |> validate_not_self()
    |> foreign_key_constraint(:requester_id)
    |> foreign_key_constraint(:addressee_id)
    |> unique_constraint(:requester_id, name: :friendships_pair_index)
    |> check_constraint(:addressee_id, name: :friendships_not_self)
  end

  defp validate_not_self(changeset) do
    if get_field(changeset, :requester_id) == get_field(changeset, :addressee_id) do
      add_error(changeset, :addressee_id, "não pode ser você mesmo")
    else
      changeset
    end
  end
end
