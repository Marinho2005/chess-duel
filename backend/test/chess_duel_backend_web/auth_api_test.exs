defmodule ChessDuelBackendWeb.AuthApiTest do
  use ChessDuelBackendWeb.ConnCase, async: true

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
end
