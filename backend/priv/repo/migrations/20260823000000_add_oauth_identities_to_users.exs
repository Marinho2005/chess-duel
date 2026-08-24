defmodule ChessDuelBackend.Repo.Migrations.AddOauthIdentitiesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_id, :string
    end

    create unique_index(:users, [:google_id], where: "google_id IS NOT NULL")
  end
end
