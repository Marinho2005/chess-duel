defmodule ChessDuelBackend.Puzzles.Attempt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "puzzle_attempts" do
    field :current_index, :integer, default: 1
    field :failed_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :outcome, :string
    field :rating_before, :integer
    field :rating_after, :integer
    field :rating_change, :integer
    field :time_spent_ms, :integer
    field :completed_at, :utc_datetime
    belongs_to :user, ChessDuelBackend.Accounts.User
    belongs_to :puzzle, ChessDuelBackend.Puzzles.Puzzle

    timestamps(type: :utc_datetime)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :user_id,
      :puzzle_id,
      :current_index,
      :failed_at,
      :resolved_at,
      :outcome,
      :rating_before,
      :rating_after,
      :rating_change,
      :time_spent_ms,
      :completed_at
    ])
    |> validate_required([:user_id, :puzzle_id, :current_index])
    |> validate_inclusion(:outcome, ["correct", "incorrect"])
    |> unique_constraint([:user_id, :puzzle_id])
  end
end
