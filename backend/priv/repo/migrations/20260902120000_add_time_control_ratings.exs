defmodule ChessDuelBackend.Repo.Migrations.AddTimeControlRatings do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :bullet_rating, :integer, null: false, default: 1200
      add :blitz_rating, :integer, null: false, default: 1200
      add :blitz_increment_rating, :integer, null: false, default: 1200
      add :rapid_rating, :integer, null: false, default: 1200
    end

    execute """
    UPDATE users SET bullet_rating = rating, blitz_rating = rating,
      blitz_increment_rating = rating, rapid_rating = rating
    """

    alter table(:rating_changes) do
      add :category, :string, null: false, default: "blitz"
    end

    execute """
    UPDATE rating_changes AS rc SET category = CASE
      WHEN g.initial_time_ms = 60000 AND g.increment_ms = 0 THEN 'bullet'
      WHEN g.initial_time_ms = 300000 AND g.increment_ms = 3000 THEN 'blitz_increment'
      WHEN g.initial_time_ms = 600000 AND g.increment_ms = 0 THEN 'rapid'
      ELSE 'blitz' END
    FROM games AS g WHERE g.id = rc.game_id
    """

    create index(:rating_changes, [:user_id, :category, :inserted_at])
  end

  def down do
    drop index(:rating_changes, [:user_id, :category, :inserted_at])
    alter table(:rating_changes), do: remove(:category)

    alter table(:users) do
      remove :bullet_rating
      remove :blitz_rating
      remove :blitz_increment_rating
      remove :rapid_rating
    end
  end
end
