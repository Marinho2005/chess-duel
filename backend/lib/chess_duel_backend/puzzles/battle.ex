defmodule ChessDuelBackend.Puzzles.Battle do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "puzzle_battles" do
    field :duration_seconds, :integer
    field :status, :string, default: "preparing"
    field :puzzle_ids, {:array, Ecto.UUID}, default: []
    field :started_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :result, :string
    field :rated_at, :utc_datetime
    belongs_to :winner, ChessDuelBackend.Accounts.User
    has_many :participants, ChessDuelBackend.Puzzles.BattleParticipant

    timestamps(type: :utc_datetime)
  end

  def changeset(battle, attrs) do
    battle
    |> cast(attrs, [
      :duration_seconds,
      :status,
      :puzzle_ids,
      :started_at,
      :ends_at,
      :finished_at,
      :result,
      :winner_id,
      :rated_at
    ])
    |> validate_required([:duration_seconds, :status, :puzzle_ids, :started_at, :ends_at])
    |> validate_inclusion(:duration_seconds, [180, 300])
    |> validate_inclusion(:status, ["preparing", "in_progress", "finished"])
    |> validate_inclusion(:result, ["player_one_wins", "player_two_wins", "draw"])
  end
end
