defmodule ChessDuelBackend.Repo.Migrations.AddAccountModeration do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
      add :account_status, :string, null: false, default: "active"
      add :suspended_until, :utc_datetime_usec
    end

    create constraint(:users, :users_role_valid, check: "role IN ('user', 'admin')")

    create constraint(:users, :users_status_valid,
             check: "account_status IN ('active', 'suspended', 'banned')"
           )

    create constraint(:users, :users_suspension_valid,
             check:
               "(account_status = 'suspended' AND suspended_until IS NOT NULL) OR (account_status <> 'suspended' AND suspended_until IS NULL)"
           )

    create index(:users, [:account_status, :suspended_until])

    create table(:moderation_actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :target_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :admin_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :action, :string, null: false
      add :reason, :text, null: false
      add :suspended_until, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:moderation_actions, [:target_user_id, :inserted_at])
    create index(:moderation_actions, [:admin_user_id])

    create constraint(:moderation_actions, :moderation_action_valid,
             check: "action IN ('suspend', 'ban', 'reactivate')"
           )

    create constraint(:moderation_actions, :moderation_reason_present,
             check: "length(btrim(reason)) > 0"
           )

    create constraint(:moderation_actions, :moderation_not_self,
             check: "target_user_id <> admin_user_id"
           )

    create constraint(:moderation_actions, :moderation_suspension_valid,
             check:
               "(action = 'suspend' AND suspended_until IS NOT NULL) OR (action <> 'suspend' AND suspended_until IS NULL)"
           )

    create index(:games, [:inserted_at, :id])
  end
end
