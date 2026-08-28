defmodule ChessDuelBackend.Accounts.GuestTest do
  use ChessDuelBackendWeb.ConnCase, async: true

  alias ChessDuelBackend.Accounts.Guest

  test "gera identidade temporaria verificavel sem criar usuario", %{conn: conn} do
    users_before = ChessDuelBackend.Repo.aggregate(ChessDuelBackend.Accounts.User, :count)

    response = conn |> post("/api/guests/session") |> json_response(200)

    assert response["token"] =~ "guest:"
    assert response["expires_in"] == 14_400
    assert response["guest"]["id"] =~ "guest-"
    assert response["guest"]["nickname"] =~ "Convidado-"
    assert {:ok, guest} = Guest.verify(response["token"])
    assert guest.id == response["guest"]["id"]
    assert ChessDuelBackend.Repo.aggregate(ChessDuelBackend.Accounts.User, :count) == users_before
  end

  test "recusa token de convidado adulterado" do
    %{token: token} = Guest.new()
    assert :error = Guest.verify(token <> "x")
  end
end
