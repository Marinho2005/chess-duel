defmodule ChessDuelBackend.Repo.Migrations.AddNicknameAndRatingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :nickname, :string, null: false
      add :rating, :integer, null: false, default: 1200
    end

    create unique_index(:users, [:nickname])
  end
end
