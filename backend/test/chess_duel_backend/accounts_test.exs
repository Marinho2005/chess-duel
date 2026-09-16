defmodule ChessDuelBackend.AccountsTest do
  use ChessDuelBackend.DataCase, async: true

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.OAuthIdentity
  alias ChessDuelBackend.Repo

  test "register_user/1 cria usuario com nickname unico, senha segura e rating inicial" do
    attrs = %{
      email: "player@example.com",
      nickname: "player_one",
      password: "password1234",
      birth_date: ~D[2000-05-20]
    }

    assert {:ok, user} = Accounts.register_user(attrs)
    assert user.nickname == "player_one"
    assert user.rating == 1200
    assert user.hashed_password
    assert user.birth_date == ~D[2000-05-20]
    refute user.password

    assert {:error, changeset} =
             Accounts.register_user(%{attrs | email: "other@example.com"})

    assert "has already been taken" in errors_on(changeset).nickname
  end

  test "register_user/1 rejeita data de nascimento futura e aceita data ausente" do
    assert {:error, changeset} =
             Accounts.register_user(%{
               email: "future-birth@example.com",
               nickname: "future_birth",
               password: "password1234",
               birth_date: Date.add(Date.utc_today(), 1)
             })

    assert "não pode ser uma data futura" in errors_on(changeset).birth_date

    assert {:ok, user} =
             Accounts.register_user(%{
               email: "no-birth@example.com",
               nickname: "no_birth",
               password: "password1234"
             })

    assert is_nil(user.birth_date)
  end

  test "update_user_profile/2 altera somente dados publicos e preserva o rating" do
    assert {:ok, user} =
             Accounts.register_user(%{
               email: "profile@example.com",
               nickname: "profile_player",
               password: "password1234"
             })

    assert {:ok, updated_user} =
             Accounts.update_user_profile(user, %{
               nickname: "new_nickname",
               country: "Brasil",
               rating: 9999,
               email: "hacker@example.com"
             })

    assert updated_user.nickname == "new_nickname"
    assert updated_user.country == "Brasil"
    assert updated_user.rating == 1200
    assert updated_user.email == "profile@example.com"
  end

  test "Google novo cria conta e logins futuros usam o ID estavel" do
    attrs = %{
      uid: "google-123",
      email: "oauth@example.com",
      name: "OAuth Player",
      avatar_url: "https://images.example.com/avatar.png",
      email_verified: true
    }

    assert {:ok, user} = Accounts.authenticate_oauth_user(:google, attrs)
    assert user.email == "oauth@example.com"
    assert user.nickname == "OAuth_Player"
    assert user.avatar_path == "https://images.example.com/avatar.png"
    assert user.rating == 1200
    assert user.confirmed_at
    refute user.hashed_password

    assert {:ok, same_user} =
             Accounts.authenticate_oauth_user(:google, %{attrs | email: nil, email_verified: false})

    assert same_user.id == user.id
    assert identity_for(user, "google").provider_uid == "google-123"
  end

  test "Google com email verificado vincula a conta local pelo email" do
    assert {:ok, local_user} =
             Accounts.register_user(%{
               email: "linked@example.com",
               nickname: "linked_player",
               password: "password1234"
             })

    assert {:ok, google_user} =
             Accounts.authenticate_oauth_user(:google, %{
               uid: "google-linked",
               email: "LINKED@example.com",
               email_verified: true
             })

    assert google_user.id == local_user.id
    assert google_user.hashed_password == local_user.hashed_password
    assert google_user.confirmed_at
    assert identity_for(local_user, "google").provider_uid == "google-linked"
  end

  test "Google gera sufixo para nickname repetido e exige email verificado" do
    assert {:ok, _user} =
             Accounts.register_user(%{
               email: "first@example.com",
               nickname: "same_name",
               password: "password1234"
             })

    assert {:ok, oauth_user} =
             Accounts.authenticate_oauth_user(:google, %{
               uid: "google-new",
               email: "second@example.com",
               nickname: "same_name",
               email_verified: true
             })

    assert oauth_user.nickname == "same_name_1"

    assert {:error, :oauth_email_required} =
             Accounts.authenticate_oauth_user(:google, %{
               uid: "google-private",
               email: nil,
               email_verified: true
             })

    assert {:error, :oauth_email_not_verified} =
             Accounts.authenticate_oauth_user(:google, %{
               uid: "google-unverified",
               email: "unverified@example.com",
               email_verified: false
             })
  end

  for provider <- [:discord, :github] do
    test "#{provider} novo cria conta e existente autentica pelo ID" do
      provider = unquote(provider)

      attrs = %{
        uid: "#{provider}-123",
        email: "#{provider}@example.com",
        nickname: "#{provider}_player"
      }

      assert {:ok, user} = Accounts.authenticate_oauth_user(provider, attrs)
      assert user.email =~ "@oauth.chessduel.invalid"
      assert identity_for(user, Atom.to_string(provider)).provider_email == attrs.email

      assert {:ok, same_user} =
               Accounts.authenticate_oauth_user(provider, %{attrs | email: "changed@example.com"})

      assert same_user.id == user.id
    end

    test "#{provider} nao vincula automaticamente por email" do
      provider = unquote(provider)

      assert {:ok, local_user} =
               Accounts.register_user(%{
                 email: "shared-#{provider}@example.com",
                 nickname: "local_#{provider}",
                 password: "password1234"
               })

      assert {:ok, oauth_user} =
               Accounts.authenticate_oauth_user(provider, %{
                 uid: "#{provider}-separate",
                 email: local_user.email,
                 nickname: "remote_#{provider}"
               })

      refute oauth_user.id == local_user.id
      assert identity_for(oauth_user, Atom.to_string(provider)).provider_email == local_user.email
    end
  end

  test "a mesma combinacao de provider e provider_uid e rejeitada pelo banco" do
    assert {:ok, first_user} =
             Accounts.authenticate_oauth_user(:discord, %{uid: "duplicate", email: nil})

    assert {:ok, second_user} =
             Accounts.register_user(%{
               email: "second-identity@example.com",
               nickname: "second_identity",
               password: "password1234"
             })

    assert {:error, changeset} =
             %OAuthIdentity{}
             |> OAuthIdentity.changeset(%{
               user_id: second_user.id,
               provider: "discord",
               provider_uid: "duplicate"
             })
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).provider
    assert identity_for(first_user, "discord")
  end

  defp identity_for(user, provider) do
    Repo.get_by!(OAuthIdentity, user_id: user.id, provider: provider)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
