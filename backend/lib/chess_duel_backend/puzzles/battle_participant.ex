defmodule ChessDuelBackend.Puzzles.BattleParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "puzzle_battle_participants" do
    field :slot, :string
    field :score, :integer, default: 0
    field :errors, :integer, default: 0
    field :puzzles_attempted, :integer, default: 0
    field :current_puzzle_index, :integer, default: 0
    belongs_to :battle, ChessDuelBackend.Puzzles.Battle
    belongs_to :user, ChessDuelBackend.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [
      :battle_id,
      :user_id,
      :slot,
      :score,
      :errors,
      :puzzles_attempted,
      :current_puzzle_index
    ])
    |> validate_required([:battle_id, :user_id, :slot])
    |> validate_inclusion(:slot, ["player_one", "player_two"])
    |> unique_constraint([:battle_id, :user_id])
    |> unique_constraint([:battle_id, :slot])
  end
end
