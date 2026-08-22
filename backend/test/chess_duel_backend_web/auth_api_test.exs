defmodule ChessDuelBackendWeb.AuthApiTest do
  use ChessDuelBackendWeb.ConnCase, async: true

  alias ChessDuelBackend.Accounts.AvatarStorage

  test "cadastro, me e logout usam bearer token revogavel", %{conn: conn} do
    register_conn =
      post(conn, "/api/users/register", %{
        "user" => %{
          "email" => "api@example.com",
          "nickname" => "api_player",
          "password" => "password1234"
        }
      })

    %{"token" => token, "user" => user} = json_response(register_conn, 201)
    assert user["nickname"] == "api_player"
    assert user["rating"] == 1200

    authenticated_conn = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    assert %{"user" => %{"id" => user_id}} =
             json_response(get(authenticated_conn, "/api/users/me"), 200)

    assert user_id == user["id"]

    assert response(delete(authenticated_conn, "/api/users/log_out"), 204)

    rejected_conn = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    assert %{"error" => "authentication_required"} =
             json_response(get(rejected_conn, "/api/users/me"), 401)
  end

  test "login rejeita credenciais invalidas e retorna token para credenciais validas", %{conn: conn} do
    attrs = %{
      "email" => "login@example.com",
      "nickname" => "login_player",
      "password" => "password1234"
    }

    assert %{"token" => _token} =
             json_response(post(conn, "/api/users/register", %{"user" => attrs}), 201)

    assert %{"error" => "invalid_email_or_password"} =
             conn
             |> post("/api/users/log_in", %{"user" => %{attrs | "password" => "wrong-password"}})
             |> json_response(401)

    assert %{"token" => token} =
             build_conn()
             |> post("/api/users/log_in", %{"user" => Map.take(attrs, ["email", "password"])})
             |> json_response(200)

    assert is_binary(token)
  end

  test "me exige autenticacao", %{conn: conn} do
    assert %{"error" => "authentication_required"} = json_response(get(conn, "/api/users/me"), 401)
  end

  test "perfil publico nao expoe email e somente o dono pode editar", %{conn: conn} do
    attrs = %{
      "email" => "public@example.com",
      "nickname" => "public_player",
      "password" => "password1234"
    }

    %{"token" => token} =
      conn
      |> post("/api/users/register", %{"user" => attrs})
      |> json_response(201)

    %{"profile" => profile} =
      build_conn()
      |> get("/api/profiles/public_player")
      |> json_response(200)

    assert profile["nickname"] == "public_player"
    assert profile["rating"] == 1200
    assert profile["inserted_at"]
    refute Map.has_key?(profile, "email")

    assert %{"error" => "authentication_required"} =
             build_conn()
             |> patch("/api/users/me", %{"user" => %{"nickname" => "intruder"}})
             |> json_response(401)

    authenticated_conn = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    %{"user" => updated_user} =
      authenticated_conn
      |> patch("/api/users/me", %{
        "user" => %{"nickname" => "updated_player", "country" => "Brasil"}
      })
      |> json_response(200)

    assert updated_user["nickname"] == "updated_player"
    assert updated_user["country"] == "Brasil"
    assert updated_user["rating"] == 1200
  end

  test "usuario autenticado envia avatar valido e ele aparece no perfil publico", %{conn: conn} do
    attrs = %{
      "email" => "avatar@example.com",
      "nickname" => "avatar_player",
      "password" => "password1234"
    }

    %{"token" => token} =
      conn
      |> post("/api/users/register", %{"user" => attrs})
      |> json_response(201)

    temporary_path = Path.join(System.tmp_dir!(), "avatar-#{Ecto.UUID.generate()}.png")
    File.write!(temporary_path, <<0x89, "PNG\r\n", 0x1A, "\n", "test-image">>)
    on_exit(fn -> File.rm(temporary_path) end)

    upload = %Plug.Upload{
      path: temporary_path,
      filename: "avatar.png",
      content_type: "image/png"
    }

    authenticated_conn = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    %{"user" => user} =
      authenticated_conn
      |> post("/api/users/me/avatar", %{"avatar" => upload})
      |> json_response(200)

    assert String.starts_with?(user["avatar_url"], "/uploads/avatars/")
    on_exit(fn -> AvatarStorage.delete(user["avatar_url"]) end)

    %{"profile" => profile} =
      build_conn()
      |> get("/api/profiles/avatar_player")
      |> json_response(200)

    assert profile["avatar_url"] == user["avatar_url"]
  end

  test "upload de avatar rejeita arquivo que nao e imagem", %{conn: conn} do
    attrs = %{
      "email" => "invalid-avatar@example.com",
      "nickname" => "invalid_avatar",
      "password" => "password1234"
    }

    %{"token" => token} =
      conn
      |> post("/api/users/register", %{"user" => attrs})
      |> json_response(201)

    temporary_path = Path.join(System.tmp_dir!(), "avatar-#{Ecto.UUID.generate()}.txt")
    File.write!(temporary_path, "isto nao e uma imagem")
    on_exit(fn -> File.rm(temporary_path) end)

    upload = %Plug.Upload{path: temporary_path, filename: "fake.png", content_type: "image/png"}
    authenticated_conn = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    assert %{"error" => "invalid_avatar_format"} =
             authenticated_conn
             |> post("/api/users/me/avatar", %{"avatar" => upload})
             |> json_response(422)
  end
end
