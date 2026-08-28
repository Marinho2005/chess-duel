defmodule ChessDuelBackend.Accounts.OAuthIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  alias ChessDuelBackend.Accounts.User

  @providers ~w(google discord github)
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_identities" do
    field :provider, :string
    field :provider_uid, :string
    field :provider_email, :string
    belongs_to :user, User

    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:user_id, :provider, :provider_uid, :provider_email])
    |> validate_required([:user_id, :provider, :provider_uid])
    |> validate_inclusion(:provider, @providers)
    |> validate_length(:provider_uid, max: 255)
    |> validate_length(:provider_email, max: 160)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:provider, :provider_uid])
  end
end
