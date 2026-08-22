defmodule ChessDuelBackend.Repo.Migrations.AddRatingSystem do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :rated_at, :utc_datetime
      add :white_rating_before, :integer
      add :white_rating_after, :integer
      add :black_rating_before, :integer
      add :black_rating_after, :integer
    end

    create table(:rating_changes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :rating_before, :integer, null: false
      add :rating_after, :integer, null: false
      add :change, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:rating_changes, [:user_id])
    create unique_index(:rating_changes, [:game_id, :user_id])
  end
end
