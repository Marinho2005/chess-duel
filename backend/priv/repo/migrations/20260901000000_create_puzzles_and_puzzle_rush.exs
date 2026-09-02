defmodule ChessDuelBackend.Repo.Migrations.CreatePuzzlesAndPuzzleRush do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :puzzle_rating, :integer, null: false, default: 1200
    end

    create table(:puzzles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :lichess_id, :string, null: false
      add :fen, :text, null: false
      add :moves, {:array, :string}, null: false
      add :rating, :integer, null: false
      add :themes, {:array, :string}, null: false, default: []
      add :popularity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:puzzles, [:lichess_id])
    create index(:puzzles, [:rating])

    create table(:puzzle_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :puzzle_id, references(:puzzles, type: :binary_id, on_delete: :delete_all), null: false
      add :current_index, :integer, null: false, default: 1
      add :failed_at, :utc_datetime
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:puzzle_attempts, [:user_id, :puzzle_id])
    create index(:puzzle_attempts, [:user_id, :resolved_at])

    create table(:puzzle_rush_scores, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :binary_id, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :score, :integer, null: false
      add :duration_seconds, :integer, null: false
      add :finished_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:puzzle_rush_scores, [:session_id])
    create index(:puzzle_rush_scores, [:user_id, :score])
  end
end
