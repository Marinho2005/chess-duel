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

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
