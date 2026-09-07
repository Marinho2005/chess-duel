defmodule ChessDuelBackend.Repo.Migrations.AddProfileViewsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :profile_views, :integer, null: false, default: 0
    end
  end
end
