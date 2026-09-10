defmodule ChessDuelBackend.Accounts.ModerationAction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "moderation_actions" do
    belongs_to :target_user, ChessDuelBackend.Accounts.User
    belongs_to :admin_user, ChessDuelBackend.Accounts.User
    field :action, Ecto.Enum, values: [:suspend, :ban, :reactivate]
    field :reason, :string
    field :suspended_until, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:target_user_id, :admin_user_id, :action, :reason, :suspended_until])
    |> update_change(:reason, &String.trim/1)
    |> validate_required([:target_user_id, :admin_user_id, :action, :reason])
    |> validate_length(:reason, min: 1, max: 2_000)
    |> foreign_key_constraint(:target_user_id)
    |> foreign_key_constraint(:admin_user_id)
    |> check_constraint(:target_user_id, name: :moderation_not_self)
  end
end
