defmodule ChessDuelBackend.Clubs.Club do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "clubs" do
    field :name, :string
    field :description, :string, default: ""
    field :avatar_path, :string
    field :join_policy, :string, default: "approval"
    belongs_to :creator, ChessDuelBackend.Accounts.User
    has_many :memberships, ChessDuelBackend.Clubs.Membership
    timestamps()
  end

  def changeset(club, attrs) do
    club
    |> cast(attrs, [:name, :description, :avatar_path, :join_policy, :creator_id])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &String.trim/1)
    |> validate_required([:name, :join_policy, :creator_id])
    |> validate_length(:name, min: 3, max: 80)
    |> validate_length(:description, max: 1_000)
    |> validate_inclusion(:join_policy, ~w(open approval))
    |> foreign_key_constraint(:creator_id)
    |> check_constraint(:join_policy, name: :clubs_valid_join_policy)
  end
end
