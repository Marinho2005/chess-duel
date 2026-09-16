defmodule ChessDuelBackend.Repo.Migrations.CreateClubs do
  use Ecto.Migration

  def change do
    create table(:clubs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text, null: false, default: ""
      add :avatar_path, :string
      add :join_policy, :string, null: false, default: "approval"
      add :creator_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      timestamps()
    end

    create constraint(:clubs, :clubs_valid_join_policy,
             check: "join_policy IN ('open', 'approval')"
           )

    create index(:clubs, [:creator_id])
    create index(:clubs, ["lower(name)"])

    create table(:club_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :club_id, references(:clubs, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "pending"
      timestamps()
    end

    create unique_index(:club_memberships, [:club_id, :user_id])
    create index(:club_memberships, [:user_id, :status])
    create index(:club_memberships, [:club_id, :status])

    create constraint(:club_memberships, :club_memberships_valid_role,
             check: "role IN ('admin', 'member')"
           )

    create constraint(:club_memberships, :club_memberships_valid_status,
             check: "status IN ('pending', 'active')"
           )

    create constraint(:club_memberships, :club_memberships_admin_must_be_active,
             check: "role <> 'admin' OR status = 'active'"
           )
  end
end
