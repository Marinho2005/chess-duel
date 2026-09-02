defmodule ChessDuelBackend.Puzzles.RushScore do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "puzzle_rush_scores" do
    field :session_id, Ecto.UUID
    field :score, :integer
    field :duration_seconds, :integer
    field :errors, :integer, default: 0
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    belongs_to :user, ChessDuelBackend.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [
      :session_id,
      :user_id,
      :score,
      :errors,
      :duration_seconds,
      :started_at,
      :finished_at
    ])
    |> validate_required([
      :session_id,
      :user_id,
      :score,
      :errors,
      :duration_seconds,
      :started_at,
      :finished_at
    ])
    |> validate_inclusion(:duration_seconds, [180, 300])
    |> unique_constraint(:session_id)
  end
end
