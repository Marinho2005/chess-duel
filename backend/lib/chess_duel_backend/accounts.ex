defmodule ChessDuelBackend.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias ChessDuelBackend.Repo

  alias ChessDuelBackend.Accounts.{OAuthIdentity, User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)
  def get_user(id), do: Repo.get(User, id)

  def get_user_by_nickname(nickname) when is_binary(nickname) do
    Repo.get_by(User, nickname: nickname)
  end

  @ranking_page_size 50

  def list_ranked_users(page \\ 1, category \\ :blitz) when is_integer(page) and page > 0 do
    base_query = from(user in User, where: not is_nil(user.confirmed_at))
    field = User.rating_field(category)

    users =
      base_query
      |> order_by([user], desc: field(user, ^field), asc: user.nickname, asc: user.id)
      |> limit(^@ranking_page_size)
      |> offset(^((page - 1) * @ranking_page_size))
      |> Repo.all()

    total = Repo.aggregate(base_query, :count)

    %{
      users: users,
      page: page,
      page_size: @ranking_page_size,
      total: total,
      total_pages: max(ceil(total / @ranking_page_size), 1)
    }
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_confirmation_token(user)
    Repo.insert!(user_token)
    UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
  end

  def confirm_user(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_confirmation_token_query(token),
         {%User{confirmed_at: nil} = user, user_token} <- Repo.one(query) do
      Repo.transact(fn ->
        with {:ok, confirmed_user} <- user |> User.confirm_changeset() |> Repo.update() do
          Repo.delete!(user_token)
          {:ok, confirmed_user}
        end
      end)
    else
      _ -> {:error, :invalid_or_expired_token}
    end
  end

  @oauth_providers [:google, :discord, :github]

  @doc "Localiza, vincula ou cria um usuario a partir de uma identidade OAuth confiavel."
  def authenticate_oauth_user(provider, attrs)
      when provider in @oauth_providers and is_map(attrs) do
    uid = attrs |> Map.get(:uid, "") |> to_string() |> String.trim()
    email = normalize_oauth_email(attrs[:email])

    cond do
      uid == "" ->
        {:error, :invalid_oauth_identity}

      user = get_user_by_oauth_identity(provider, uid) ->
        {:ok, user}

      provider == :google ->
        authenticate_new_google(uid, email, attrs)

      provider in [:discord, :github] ->
        create_oauth_user(provider, uid, email, attrs)
    end
  end

  defp authenticate_new_google(uid, email, attrs) do
    cond do
      attrs[:email_verified] != true -> {:error, :oauth_email_not_verified}
      email == "" -> {:error, :oauth_email_required}
      user = get_user_by_email(email) -> link_oauth_identity(user, :google, uid, email)
      true -> create_oauth_user(:google, uid, email, attrs)
    end
  end

  defp create_oauth_user(provider, uid, email, attrs) do
    user_email = if provider == :google, do: email, else: oauth_internal_email(provider, uid)

    oauth_attrs =
      %{
        email: user_email,
        nickname:
          unique_oauth_nickname(
            attrs[:nickname] || attrs[:name] || blank_to_nil(email) || Atom.to_string(provider)
          ),
        avatar_path: normalize_oauth_avatar(attrs[:avatar_url]),
        confirmed_at: NaiveDateTime.utc_now(:second)
      }

    result =
      Repo.transact(fn ->
        case get_user_by_oauth_identity(provider, uid) do
          %User{} = user ->
            {:ok, user}

          nil ->
            with {:ok, user} <-
                   %User{} |> User.oauth_registration_changeset(oauth_attrs) |> Repo.insert(),
                 {:ok, _identity} <- insert_oauth_identity(user, provider, uid, email) do
              {:ok, user}
            end
        end
      end)

    case result do
      {:error, _reason} = error ->
        # Duas callbacks simultaneas podem disputar a mesma constraint. Depois
        # do rollback, reutilizamos a identidade que venceu a corrida.
        case get_user_by_oauth_identity(provider, uid) do
          %User{} = user -> {:ok, user}
          nil -> error
        end

      success ->
        success
    end
  end

  defp link_oauth_identity(user, provider, uid, email) do
    case insert_oauth_identity(user, provider, uid, email) do
      {:ok, _identity} ->
        if user.confirmed_at do
          {:ok, user}
        else
          user
          |> Ecto.Changeset.change(confirmed_at: NaiveDateTime.utc_now(:second))
          |> Repo.update()
        end

      {:error, _changeset} = error ->
        case get_user_by_oauth_identity(provider, uid) do
          %User{id: user_id} = existing when user_id == user.id -> {:ok, existing}
          %User{} -> {:error, :oauth_identity_conflict}
          nil -> error
        end
    end
  end

  defp insert_oauth_identity(user, provider, uid, email) do
    %OAuthIdentity{}
    |> OAuthIdentity.changeset(%{
      user_id: user.id,
      provider: Atom.to_string(provider),
      provider_uid: uid,
      provider_email: blank_to_nil(email)
    })
    |> Repo.insert()
  end

  defp get_user_by_oauth_identity(provider, uid) do
    from(identity in OAuthIdentity,
      join: user in assoc(identity, :user),
      where: identity.provider == ^Atom.to_string(provider) and identity.provider_uid == ^uid,
      select: user
    )
    |> Repo.one()
  end

  defp oauth_internal_email(provider, uid) do
    digest = :crypto.hash(:sha256, uid) |> Base.url_encode64(padding: false)
    "#{provider}-#{digest}@oauth.chessduel.invalid"
  end

  defp unique_oauth_nickname(source) do
    base =
      source
      |> to_string()
      |> String.split("@", parts: 2)
      |> hd()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^a-zA-Z0-9_]+/u, "_")
      |> String.trim("_")
      |> String.slice(0, 32)
      |> ensure_nickname_length()

    Stream.iterate(0, &(&1 + 1))
    |> Enum.find_value(fn
      0 ->
        if is_nil(get_user_by_nickname(base)), do: base

      suffix ->
        suffix_text = "_#{suffix}"
        candidate = String.slice(base, 0, 32 - String.length(suffix_text)) <> suffix_text
        if is_nil(get_user_by_nickname(candidate)), do: candidate
    end)
  end

  defp ensure_nickname_length(value) when byte_size(value) >= 3, do: value
  defp ensure_nickname_length(value), do: String.pad_trailing(value, 3, "_")

  defp normalize_oauth_avatar(value) when is_binary(value) do
    value = String.trim(value)
    if String.starts_with?(value, ["https://", "http://"]), do: value
  end

  defp normalize_oauth_avatar(_value), do: nil

  defp normalize_oauth_email(value) when is_binary(value), do: String.trim(value)
  defp normalize_oauth_email(_value), do: ""
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  ## Settings

  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  def update_user_avatar(%User{} = user, avatar_path) when is_binary(avatar_path) do
    user
    |> User.avatar_changeset(avatar_path)
    |> Repo.update()
  end

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, NaiveDateTime) do
    NaiveDateTime.after?(ts, NaiveDateTime.utc_now() |> NaiveDateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `ChessDuelBackend.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `ChessDuelBackend.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def generate_user_api_token(user) do
    {encoded_token, user_token} = UserToken.build_api_token(user)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_user_by_api_token(encoded_token) when is_binary(encoded_token) do
    with {:ok, query} <- UserToken.verify_api_token_query(encoded_token) do
      Repo.one(query)
    else
      :error -> nil
    end
  end

  def get_user_by_api_token(_token), do: nil

  def delete_user_api_token(encoded_token) when is_binary(encoded_token) do
    with {:ok, query} <- UserToken.api_token_query(encoded_token) do
      Repo.delete_all(query)
      :ok
    else
      :error -> :ok
    end
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
