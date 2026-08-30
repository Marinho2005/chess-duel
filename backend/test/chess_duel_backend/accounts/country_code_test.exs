defmodule ChessDuelBackend.Accounts.CountryCodeTest do
  use ChessDuelBackend.DataCase, async: true

  alias ChessDuelBackend.Accounts.User

  test "normaliza código ISO válido e aceita jogador sem país" do
    valid = User.profile_changeset(%User{}, %{nickname: "country_player", country_code: "br"})
    assert valid.valid?
    assert Ecto.Changeset.get_change(valid, :country_code) == "BR"

    without_country = User.profile_changeset(%User{}, %{nickname: "no_country", country_code: nil})
    assert without_country.valid?
  end

  test "rejeita código fora do formato ISO alpha-2" do
    changeset = User.profile_changeset(%User{}, %{nickname: "bad_country", country_code: "BRA"})
    refute changeset.valid?
    assert {:country_code, {_message, _options}} = List.keyfind(changeset.errors, :country_code, 0)
  end
end
