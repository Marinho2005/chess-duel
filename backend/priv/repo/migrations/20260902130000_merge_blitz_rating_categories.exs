defmodule ChessDuelBackend.Repo.Migrations.MergeBlitzRatingCategories do
  use Ecto.Migration

  def up do
    execute "UPDATE rating_changes SET category = 'blitz' WHERE category = 'blitz_increment'"
    alter table(:users), do: remove(:blitz_increment_rating)
  end

  def down do
    alter table(:users), do: add(:blitz_increment_rating, :integer, null: false, default: 1200)
    execute "UPDATE users SET blitz_increment_rating = blitz_rating"
  end
end
