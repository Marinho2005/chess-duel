defmodule ChessDuelBackend.Repo.Migrations.CreateGameAnalyses do
  use Ecto.Migration

  def change do
    create table(:game_analyses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :results, :map
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_analyses, [:game_id])
    create constraint(:game_analyses, :valid_status,
             check: "status IN ('pending', 'processing', 'completed', 'failed')")
  end
end
