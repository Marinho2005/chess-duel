defmodule ChessDuelBackendWeb.FriendshipControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: true
  alias ChessDuelBackend.{Accounts, Repo, Social}
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Social.Friendship

  setup do
    users =
      for name <- ~w(alice bob carol) do
        suffix = System.unique_integer([:positive])

        {:ok, user} =
          Accounts.register_user(%{
            email: "#{name}#{suffix}@example.com",
            nickname: "#{name}#{suffix}",
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

  defp create(a, b),
    do:
      auth(a)
      |> post("/api/friendships", %{user_id: b.id})
      |> json_response(200)
      |> Map.fetch!("friendship")

  defp list(user, status),
    do:
      auth(user)
      |> get("/api/friendships?status=#{status}")
      |> json_response(200)
      |> Map.fetch!("friendships")

  test "pedido, direções, aceite, duplicidade e remoção por ambos os lados", %{a: a, b: b} do
    f = create(a, b)
    assert f["direction"] == "outgoing"
    assert [%{"direction" => "incoming", "user" => %{"id" => id}}] = list(b, "pending")
    assert id == a.id
    duplicate = auth(a) |> post("/api/friendships", %{user_id: b.id}) |> json_response(409)
    assert duplicate["error"] == "already_pending"
    assert is_binary(duplicate["message"])
    auth(b) |> patch("/api/friendships/#{f["id"]}/accept") |> json_response(200)
    assert [%{"user" => %{"id" => bid}}] = list(a, "accepted")
    assert bid == b.id
    assert length(list(b, "accepted")) == 1
    assert list(b, "pending") == []
    auth(b) |> post("/api/friendships", %{user_id: a.id}) |> json_response(409)
    auth(b) |> delete("/api/friendships/#{f["id"]}") |> response(204)
    assert list(a, "accepted") == []
    assert list(b, "accepted") == []
    f = create(a, b)
    auth(b) |> patch("/api/friendships/#{f["id"]}/accept") |> json_response(200)
    auth(a) |> delete("/api/friendships/#{f["id"]}") |> response(204)
    assert list(b, "accepted") == []
  end

  test "cancelamento só pelo remetente e autorização das ações", %{a: a, b: b, c: c} do
    f = create(a, b)

    for action <- ~w(accept decline) do
      auth(a) |> patch("/api/friendships/#{f["id"]}/#{action}") |> json_response(403)
      auth(c) |> patch("/api/friendships/#{f["id"]}/#{action}") |> json_response(404)
    end

    auth(b) |> delete("/api/friendships/#{f["id"]}") |> json_response(403)
    auth(c) |> delete("/api/friendships/#{f["id"]}") |> json_response(404)
    assert list(c, "pending") == []
    auth(a) |> delete("/api/friendships/#{f["id"]}") |> response(204)
    assert list(a, "pending") == []
    assert list(b, "pending") == []
  end

  test "pedidos mútuos aceitam automaticamente sem duplicar", %{a: a, b: b} do
    f = create(a, b)
    mutual = auth(b) |> post("/api/friendships", %{username: a.nickname}) |> json_response(200)
    assert mutual["friendship"]["id"] == f["id"]
    assert mutual["friendship"]["status"] == "accepted"
    assert Repo.aggregate(Friendship, :count) == 1
    auth(b) |> patch("/api/friendships/#{f["id"]}/decline") |> json_response(409)
  end

  test "friends?/2 reconhece somente amizades aceitas", %{a: a, b: b, c: c} do
    f = create(a, b)
    refute Social.friends?(a.id, b.id)
    refute Social.friends?(a.id, c.id)

    auth(b) |> patch("/api/friendships/#{f["id"]}/accept") |> json_response(200)
    assert Social.friends?(a.id, b.id)
    assert Social.friends?(b.id, a.id)
  end

  test "recusa e reenvio reutilizam o par e atualizam a direção", %{a: a, b: b} do
    f = create(a, b)
    auth(b) |> patch("/api/friendships/#{f["id"]}/decline") |> json_response(200)
    assert list(a, "pending") == []
    assert length(list(b, "declined")) == 1
    resent = create(b, a)
    assert resent["id"] == f["id"]
    assert resent["status"] == "pending"
    assert resent["user"]["id"] == a.id
    auth(b) |> patch("/api/friendships/#{f["id"]}/accept") |> json_response(403)
    auth(a) |> patch("/api/friendships/#{f["id"]}/accept") |> json_response(200)
  end

  test "validação de destinatário, UUID, status e autenticação", %{a: a} do
    auth(a) |> post("/api/friendships", %{user_id: a.id}) |> json_response(422)
    auth(a) |> post("/api/friendships", %{user_id: "invalid"}) |> json_response(404)
    auth(a) |> post("/api/friendships", %{user_id: Ecto.UUID.generate()}) |> json_response(404)
    auth(a) |> post("/api/friendships", %{}) |> json_response(422)
    auth(a) |> patch("/api/friendships/invalid/accept") |> json_response(404)
    auth(a) |> get("/api/friendships?status=invalid") |> json_response(422)

    for path <- ["/api/friendships", "/api/users/search?q=alice"] do
      build_conn() |> get(path) |> json_response(401)
    end

    build_conn() |> post("/api/friendships", %{user_id: a.id}) |> json_response(401)

    for action <- ~w(accept decline) do
      build_conn()
      |> patch("/api/friendships/#{Ecto.UUID.generate()}/#{action}")
      |> json_response(401)
    end

    build_conn() |> delete("/api/friendships/#{Ecto.UUID.generate()}") |> json_response(401)
  end

  test "changeset impede autoamizade e banco impede duplicidade invertida", %{a: a, b: b} do
    refute Friendship.changeset(%Friendship{}, %{requester_id: a.id, addressee_id: a.id}).valid?
    {:ok, _} = Social.request(a.id, %{"user_id" => b.id})

    assert {:error, changeset} =
             Repo.insert(
               Friendship.changeset(%Friendship{}, %{requester_id: b.id, addressee_id: a.id})
             )

    assert {_, metadata} = changeset.errors[:requester_id]
    assert metadata[:constraint] == :unique
  end

  test "busca parcial ignora caixa, exclui a si mesmo e não expõe dados privados", %{a: a, b: b} do
    response =
      auth(a) |> get("/api/users/search", %{q: String.upcase(b.nickname)}) |> json_response(200)

    assert [player] = response["users"]
    assert player["id"] == b.id
    refute Map.has_key?(player, "email")
    refute Map.has_key?(player, "hashed_password")
    assert player["status"] == "offline"

    for term <- [a.nickname, "b", "%", "__"] do
      assert %{"users" => []} =
               auth(a) |> get("/api/users/search", %{q: term}) |> json_response(200)
    end
  end
end
