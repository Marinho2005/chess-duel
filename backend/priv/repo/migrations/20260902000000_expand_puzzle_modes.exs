defmodule ChessDuelBackend.Repo.Migrations.ExpandPuzzleModes do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :battle_rating, :integer, null: false, default: 1200
    end

    alter table(:puzzle_attempts) do
      add :outcome, :string
      add :rating_before, :integer
      add :rating_after, :integer
      add :rating_change, :integer
      add :time_spent_ms, :bigint
      add :completed_at, :utc_datetime
    end

    create constraint(:puzzle_attempts, :puzzle_attempts_outcome_check,
             check: "outcome IS NULL OR outcome IN ('correct', 'incorrect')"
           )

    alter table(:puzzle_rush_scores) do
      add :errors, :integer, null: false, default: 0
      add :started_at, :utc_datetime
    end

    execute "UPDATE puzzle_rush_scores SET started_at = inserted_at WHERE started_at IS NULL", ""
    execute "ALTER TABLE puzzle_rush_scores ALTER COLUMN started_at SET NOT NULL", ""

    create constraint(:puzzle_rush_scores, :puzzle_rush_duration_check,
             check: "duration_seconds IN (180, 300)"
           )

    create index(:puzzle_rush_scores, [:user_id, :duration_seconds, :score])

    create table(:puzzle_battles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :duration_seconds, :integer, null: false
      add :status, :string, null: false, default: "preparing"
      add :puzzle_ids, {:array, :binary_id}, null: false
      add :started_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :result, :string
      add :winner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :rated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create constraint(:puzzle_battles, :puzzle_battles_duration_check,
             check: "duration_seconds IN (180, 300)"
           )

    create constraint(:puzzle_battles, :puzzle_battles_status_check,
             check: "status IN ('preparing', 'in_progress', 'finished')"
           )

    create constraint(:puzzle_battles, :puzzle_battles_result_check,
             check: "result IS NULL OR result IN ('player_one_wins', 'player_two_wins', 'draw')"
           )

    create table(:puzzle_battle_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :battle_id, references(:puzzle_battles, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :slot, :string, null: false
      add :score, :integer, null: false, default: 0
      add :errors, :integer, null: false, default: 0
      add :puzzles_attempted, :integer, null: false, default: 0
      add :current_puzzle_index, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:puzzle_battle_participants, [:battle_id, :user_id])
    create unique_index(:puzzle_battle_participants, [:battle_id, :slot])
    create index(:puzzle_battle_participants, [:user_id, :inserted_at])

    create constraint(:puzzle_battle_participants, :puzzle_battle_participants_slot_check,
             check: "slot IN ('player_one', 'player_two')"
           )

    create table(:battle_rating_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :battle_id, references(:puzzle_battles, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :rating_before, :integer, null: false
      add :rating_after, :integer, null: false
      add :change, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:battle_rating_changes, [:battle_id, :user_id])
    create index(:battle_rating_changes, [:user_id, :inserted_at])
  end
end
