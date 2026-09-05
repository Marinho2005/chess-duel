defmodule ChessDuelBackend.Ratings.RatingChange do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rating_changes" do
    belongs_to :user, ChessDuelBackend.Accounts.User
    belongs_to :game, ChessDuelBackend.Games.Game
    field :rating_before, :integer
    field :rating_after, :integer
    field :change, :integer
    field :category, Ecto.Enum, values: [:bullet, :blitz, :rapid], default: :blitz

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(rating_change, attrs) do
    rating_change
    |> cast(attrs, [:user_id, :game_id, :rating_before, :rating_after, :change, :category])
    |> validate_required([:user_id, :game_id, :rating_before, :rating_after, :change, :category])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:game_id)
    |> unique_constraint([:game_id, :user_id])
  end
end
