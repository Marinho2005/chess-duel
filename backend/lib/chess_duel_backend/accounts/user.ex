defmodule ChessDuelBackend.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :nickname, :string
    field :country, :string
    field :avatar_path, :string
    field :google_id, :string
    field :rating, :integer, default: 1200
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime
    field :authenticated_at, :naive_datetime, virtual: true

    timestamps()
  end

  @doc "Changeset usado no cadastro local por email e senha."
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :nickname, :password])
    |> validate_email(opts)
    |> validate_nickname(opts)
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc "Changeset dos dados publicos editaveis do perfil."
  def profile_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:nickname, :country])
    |> validate_nickname(opts)
    |> validate_length(:country, max: 56)
  end

  def avatar_changeset(user, avatar_path) do
    change(user, avatar_path: avatar_path)
  end

  @doc "Changeset para criar uma conta autenticada por um provedor OAuth."
  def oauth_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :nickname, :avatar_path, :google_id, :confirmed_at])
    |> validate_email([])
    |> validate_nickname([])
    |> validate_required([:confirmed_at])
    |> validate_length(:avatar_path, max: 2_048)
    |> oauth_constraints()
  end

  @doc "Changeset para vincular uma identidade OAuth a uma conta existente."
  def oauth_link_changeset(user, :google, uid) do
    field = :google_id

    user
    |> change(%{field => uid, confirmed_at: NaiveDateTime.utc_now(:second)})
    |> validate_required([field, :confirmed_at])
    |> oauth_constraints()
  end

  defp oauth_constraints(changeset) do
    changeset
    |> unique_constraint(:google_id)
  end

  @doc false
  def rating_changeset(user, rating) when is_integer(rating) do
    change(user, rating: rating)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, ChessDuelBackend.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp validate_nickname(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:nickname])
      |> validate_length(:nickname, min: 3, max: 32)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:nickname, ChessDuelBackend.Repo)
      |> unique_constraint(:nickname)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%ChessDuelBackend.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
