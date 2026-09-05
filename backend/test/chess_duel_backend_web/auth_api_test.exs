defmodule ChessDuelBackendWeb.AuthApiTest do
  use ChessDuelBackendWeb.ConnCase, async: true

  alias ChessDuelBackend.Accounts.AvatarStorage
  alias ChessDuelBackend.{Accounts, Repo}
  alias ChessDuelBackend.Accounts.{User, UserToken}

  test "cadastro exige confirmacao antes de login, me e logout usam token revogavel", %{conn: conn} do
    register_conn =
      post(conn, "/api/users/register", %{
        "user" => %{
          "email" => "api@example.com",
          "nickname" => "api_player",
          "password" => "password1234"
        }
      })

    assert %{
             "status" => "pending_confirmation",
             "message" => "Verifique seu email para confirmar sua conta antes de fazer login."
           } =
             json_response(register_conn, 201)

    assert %{"error" => "email_not_confirmed"} =
             conn
             |> post("/api/users/log_in", %{
               "user" => %{"email" => "api@example.com", "password" => "password1234"}
             })
             |> json_response(403)

    user = Accounts.get_user_by_email("api@example.com")
    confirm_user!(user)

    %{"token" => token, "user" => logged_user} =
      build_conn()
      |> post("/api/users/log_in", %{
        "user" => %{"email" => "api@example.com", "password" => "password1234"}
      })
      |> json_response(200)

    authenticated_conn = put_req_header(build_conn(), "authorization", "Bearer #{token}")

    assert %{"user" => %{"id" => user_id}} =
             json_response(get(authenticated_conn, "/api/users/me"), 200)

    assert user_id == logged_user["id"]

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

    assert %{"status" => "pending_confirmation"} =
             json_response(post(conn, "/api/users/register", %{"user" => attrs}), 201)

    assert %{"error" => "invalid_email_or_password"} =
             conn
             |> post("/api/users/log_in", %{"user" => %{attrs | "password" => "wrong-password"}})
             |> json_response(401)

    confirm_user!(Accounts.get_user_by_email(attrs["email"]))

    assert %{"token" => token} =
             build_conn()
             |> post("/api/users/log_in", %{"user" => Map.take(attrs, ["email", "password"])})
             |> json_response(200)

    assert is_binary(token)
  end

  test "me exige autenticacao", %{conn: conn} do
    assert %{"error" => "authentication_required"} = json_response(get(conn, "/api/users/me"), 401)
  end

  test "perfil publico nao expoe email e somente o dono pode editar" do
    attrs = %{
      "email" => "public@example.com",
      "nickname" => "public_player",
      "password" => "password1234"
    }

    token = register_confirmed_token!(attrs)

    %{"profile" => profile} =
      build_conn()
      |> get("/api/profiles/public_player")
      |> json_response(200)

    assert profile["nickname"] == "public_player"
    assert profile["rating"] == 1200
    assert profile["status"] == "offline"
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

  test "usuario autenticado envia avatar valido e ele aparece no perfil publico" do
    attrs = %{
      "email" => "avatar@example.com",
      "nickname" => "avatar_player",
      "password" => "password1234"
    }

    token = register_confirmed_token!(attrs)

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

  test "upload de avatar rejeita arquivo que nao e imagem" do
    attrs = %{
      "email" => "invalid-avatar@example.com",
      "nickname" => "invalid_avatar",
      "password" => "password1234"
    }

    token = register_confirmed_token!(attrs)

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

  test "confirma email com token valido e rejeita reutilizacao", %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        email: "confirmation@example.com",
        nickname: "confirmation_player",
        password: "password1234"
      })

    {encoded_token, user_token} = UserToken.build_confirmation_token(user)
    Repo.insert!(user_token)

    assert %{"status" => "confirmed"} =
             conn
             |> post("/api/users/confirm/#{encoded_token}")
             |> json_response(200)

    assert Accounts.get_user!(user.id).confirmed_at

    assert %{"error" => "invalid_or_expired_confirmation_token"} =
             build_conn()
             |> post("/api/users/confirm/#{encoded_token}")
             |> json_response(422)
  end

  defp register_confirmed_token!(attrs) do
    {:ok, user} = Accounts.register_user(attrs)
    user = confirm_user!(user)
    Accounts.generate_user_api_token(user)
  end

  defp confirm_user!(user) do
    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end
end
