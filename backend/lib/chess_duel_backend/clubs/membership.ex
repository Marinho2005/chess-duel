defmodule ChessDuelBackend.Clubs.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "club_memberships" do
    belongs_to :club, ChessDuelBackend.Clubs.Club
    belongs_to :user, ChessDuelBackend.Accounts.User
    field :role, :string, default: "member"
    field :status, :string, default: "pending"
    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:club_id, :user_id, :role, :status])
    |> validate_required([:club_id, :user_id, :role, :status])
    |> validate_inclusion(:role, ~w(admin member))
    |> validate_inclusion(:status, ~w(pending active))
    |> foreign_key_constraint(:club_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:club_id, :user_id])
    |> check_constraint(:role, name: :club_memberships_valid_role)
    |> check_constraint(:status, name: :club_memberships_valid_status)
  end
end
