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

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
