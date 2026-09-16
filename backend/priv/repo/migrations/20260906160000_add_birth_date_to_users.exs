defmodule ChessDuelBackend.Repo.Migrations.AddBirthDateToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :birth_date, :date, null: true
    end
  end
end
