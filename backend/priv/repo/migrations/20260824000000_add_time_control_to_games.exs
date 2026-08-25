defmodule ChessDuelBackend.Repo.Migrations.AddTimeControlToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :initial_time_ms, :integer, null: false, default: 180_000
      add :increment_ms, :integer, null: false, default: 0
    end

    create constraint(:games, :games_initial_time_must_be_positive,
             check: "initial_time_ms > 0"
           )

    create constraint(:games, :games_increment_must_be_non_negative,
             check: "increment_ms >= 0"
           )
  end
end
