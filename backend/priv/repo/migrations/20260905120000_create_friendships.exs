defmodule ChessDuelBackend.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :requester_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :addressee_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      timestamps()
    end

    create unique_index(
             :friendships,
             ["LEAST(requester_id, addressee_id)", "GREATEST(requester_id, addressee_id)"],
             name: :friendships_pair_index
           )

    create index(:friendships, [:requester_id, :status])
    create index(:friendships, [:addressee_id, :status])
    create constraint(:friendships, :friendships_not_self, check: "requester_id <> addressee_id")

    create constraint(:friendships, :friendships_valid_status,
             check: "status IN ('pending', 'accepted', 'declined')"
           )
  end
end
