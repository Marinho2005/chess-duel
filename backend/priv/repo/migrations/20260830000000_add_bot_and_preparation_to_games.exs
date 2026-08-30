defmodule ChessDuelBackend.Repo.Migrations.AddBotAndPreparationToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :bot_id, :string
      add :bot_color, :string
      add :preparation_ends_at, :utc_datetime_usec
    end

    create index(:games, [:bot_id])
  end
end
