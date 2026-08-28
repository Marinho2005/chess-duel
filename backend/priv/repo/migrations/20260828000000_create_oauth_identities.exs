defmodule ChessDuelBackend.Repo.Migrations.CreateOauthIdentities do
  use Ecto.Migration

  def up do
    create table(:oauth_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_uid, :string, null: false
      add :provider_email, :citext

      timestamps()
    end

    create index(:oauth_identities, [:user_id])
    create unique_index(:oauth_identities, [:provider, :provider_uid])

    execute """
    INSERT INTO oauth_identities
      (id, user_id, provider, provider_uid, provider_email, inserted_at, updated_at)
    SELECT
      gen_random_uuid(), id, 'google', google_id, email, NOW(), NOW()
    FROM users
    WHERE google_id IS NOT NULL
    """

    drop_if_exists unique_index(:users, [:google_id], where: "google_id IS NOT NULL")

    alter table(:users) do
      remove :google_id
    end
  end

  def down do
    alter table(:users) do
      add :google_id, :string
    end

    execute """
    UPDATE users
    SET google_id = oauth_identities.provider_uid
    FROM oauth_identities
    WHERE oauth_identities.user_id = users.id
      AND oauth_identities.provider = 'google'
    """

    create unique_index(:users, [:google_id], where: "google_id IS NOT NULL")
    drop table(:oauth_identities)
  end
end
