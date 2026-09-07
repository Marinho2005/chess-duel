defmodule ChessDuelBackendWeb.ClubControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: true
  alias ChessDuelBackend.{Accounts, Repo}
  alias ChessDuelBackend.Accounts.User

  setup do
    users =
      for name <- ~w(club_alice club_bob club_carol) do
        {:ok, user} =
          Accounts.register_user(%{
            email: "#{name}-#{System.unique_integer([:positive])}@example.com",
            nickname: "#{name}_#{System.unique_integer([:positive])}",
            password: "password1234"
          })

        Repo.update!(User.confirm_changeset(user))
      end

    [a, b, c] = users
    %{a: a, b: b, c: c}
  end

  defp auth(user),
    do:
      put_req_header(
        build_conn(),
        "authorization",
        "Bearer #{Accounts.generate_user_api_token(user)}"
      )

  defp create(user, policy, name \\ "Clube dos testes") do
    auth(user)
    |> post("/api/clubs", %{club: %{name: name, description: "Descrição", join_policy: policy}})
    |> json_response(201)
    |> get_in(["club"])
  end

  defp show(user, id),
    do: auth(user) |> get("/api/clubs/#{id}") |> json_response(200) |> get_in(["club"])

  test "cria clube aberto, busca, entra diretamente e remove membro", %{a: a, b: b} do
    club = create(a, "open", "Cavalos Abertos")
    details = show(a, club["id"])
    assert details["can_administer"]
    assert [%{"role" => "admin", "user_id" => creator}] = details["members"]
    assert creator == a.id

    listing = auth(b) |> get("/api/clubs?q=CAVALOS&page=1") |> json_response(200)
    assert [%{"id" => id, "member_count" => 1}] = listing["clubs"]
    assert id == club["id"]
    joined = auth(b) |> post("/api/clubs/#{id}/join") |> json_response(200)
    assert joined["membership"]["status"] == "active"
    assert length(show(a, id)["members"]) == 2

    membership = Enum.find(show(a, id)["members"], &(&1["user_id"] == b.id))
    auth(a) |> delete("/api/clubs/#{id}/memberships/#{membership["id"]}") |> response(204)
    assert Enum.map(show(a, id)["members"], & &1["user_id"]) == [a.id]
  end

  test "clube por aprovação só inclui usuário após admin aprovar", %{a: a, b: b, c: c} do
    club = create(a, "approval")
    request = auth(c) |> post("/api/clubs/#{club["id"]}/join") |> json_response(200)
    assert request["membership"]["status"] == "pending"
    refute Enum.any?(show(a, club["id"])["members"], &(&1["user_id"] == c.id))
    assert [pending] = show(a, club["id"])["pending_memberships"]
    assert pending["user_id"] == c.id
    assert show(b, club["id"])["pending_memberships"] == []

    auth(b)
    |> patch("/api/clubs/#{club["id"]}/memberships/#{pending["id"]}/approve")
    |> json_response(403)

    auth(a)
    |> patch("/api/clubs/#{club["id"]}/memberships/#{pending["id"]}/approve")
    |> json_response(200)

    assert Enum.any?(show(a, club["id"])["members"], &(&1["user_id"] == c.id))
  end

  test "administrador promove membro e novo admin edita e recusa pedidos", %{a: a, b: b, c: c} do
    club = create(a, "open")
    auth(b) |> post("/api/clubs/#{club["id"]}/join") |> json_response(200)
    b_membership = Enum.find(show(a, club["id"])["members"], &(&1["user_id"] == b.id))

    promoted =
      auth(a)
      |> patch("/api/clubs/#{club["id"]}/memberships/#{b_membership["id"]}/promote")
      |> json_response(200)

    assert promoted["membership"]["role"] == "admin"

    updated =
      auth(b)
      |> patch("/api/clubs/#{club["id"]}", %{club: %{name: "Nome editado", join_policy: "approval"}})
      |> json_response(200)

    assert updated["club"]["name"] == "Nome editado"
    auth(c) |> post("/api/clubs/#{club["id"]}/join") |> json_response(200)
    [pending] = show(b, club["id"])["pending_memberships"]

    auth(b)
    |> patch("/api/clubs/#{club["id"]}/memberships/#{pending["id"]}/decline")
    |> json_response(200)

    assert show(b, club["id"])["pending_memberships"] == []
  end

  test "protege administração, duplicidade e último administrador", %{a: a, b: b} do
    club = create(a, "open")
    auth(b) |> patch("/api/clubs/#{club["id"]}", %{club: %{name: "Ataque"}}) |> json_response(403)
    auth(b) |> post("/api/clubs/#{club["id"]}/join") |> json_response(200)
    auth(b) |> post("/api/clubs/#{club["id"]}/join") |> json_response(409)
    details = show(a, club["id"])
    admin = Enum.find(details["members"], &(&1["user_id"] == a.id))
    auth(a) |> delete("/api/clubs/#{club["id"]}/memberships/#{admin["id"]}") |> json_response(409)
    member = Enum.find(details["members"], &(&1["user_id"] == b.id))

    auth(b)
    |> patch("/api/clubs/#{club["id"]}/memberships/#{member["id"]}/promote")
    |> json_response(403)
  end

  test "valida dados, ids e autenticação", %{a: a} do
    response =
      auth(a)
      |> post("/api/clubs", %{club: %{name: "x", join_policy: "invalid"}})
      |> json_response(422)

    assert response["error"] == "validation_failed"
    auth(a) |> get("/api/clubs/invalid") |> json_response(404)
    build_conn() |> get("/api/clubs") |> json_response(401)

    build_conn()
    |> post("/api/clubs", %{club: %{name: "Clube", join_policy: "open"}})
    |> json_response(401)
  end
end
