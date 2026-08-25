defmodule ChessDuelBackend.AccountsTest do
  use ChessDuelBackend.DataCase, async: true

  alias ChessDuelBackend.Accounts

  test "register_user/1 cria usuario com nickname unico, senha segura e rating inicial" do
    attrs = %{email: "player@example.com", nickname: "player_one", password: "password1234"}

    assert {:ok, user} = Accounts.register_user(attrs)
    assert user.nickname == "player_one"
    assert user.rating == 1200
    assert user.hashed_password
    refute user.password

    assert {:error, changeset} =
             Accounts.register_user(%{attrs | email: "other@example.com"})

    assert "has already been taken" in errors_on(changeset).nickname
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

  test "authenticate_oauth_user/2 cria uma unica conta Google com rating padrao" do
    attrs = %{
      uid: "google-123",
      email: "oauth@example.com",
      name: "OAuth Player",
      avatar_url: "https://images.example.com/avatar.png"
    }

    assert {:ok, user} = Accounts.authenticate_oauth_user(:google, attrs)
    assert user.google_id == "google-123"
    assert user.email == "oauth@example.com"
    assert user.nickname == "OAuth_Player"
    assert user.avatar_path == "https://images.example.com/avatar.png"
    assert user.rating == 1200
    assert user.confirmed_at
    refute user.hashed_password

    assert {:ok, same_user} =
             Accounts.authenticate_oauth_user(:google, %{attrs | email: nil})

    assert same_user.id == user.id
  end

  test "authenticate_oauth_user/2 vincula Google a conta local pelo email" do
    assert {:ok, local_user} =
             Accounts.register_user(%{
               email: "linked@example.com",
               nickname: "linked_player",
               password: "password1234"
             })

    assert {:ok, google_user} =
             Accounts.authenticate_oauth_user(:google, %{
               uid: "google-linked",
               email: "LINKED@example.com"
             })

    assert google_user.id == local_user.id
    assert google_user.google_id == "google-linked"
    assert google_user.hashed_password == local_user.hashed_password
    assert google_user.confirmed_at
  end

  test "authenticate_oauth_user/2 gera sufixo para nickname repetido e exige email" do
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
               nickname: "same_name"
             })

    assert oauth_user.nickname == "same_name_1"

    assert {:error, :oauth_email_required} =
             Accounts.authenticate_oauth_user(:google, %{uid: "google-private", email: nil})
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
