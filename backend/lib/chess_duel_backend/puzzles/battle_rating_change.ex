defmodule ChessDuelBackend.Puzzles.BattleRatingChange do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "battle_rating_changes" do
    field :rating_before, :integer
    field :rating_after, :integer
    field :change, :integer
    belongs_to :battle, ChessDuelBackend.Puzzles.Battle
    belongs_to :user, ChessDuelBackend.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [:battle_id, :user_id, :rating_before, :rating_after, :change])
    |> validate_required([:battle_id, :user_id, :rating_before, :rating_after, :change])
    |> unique_constraint([:battle_id, :user_id])
  end
end
