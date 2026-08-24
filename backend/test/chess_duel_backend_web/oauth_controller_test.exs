defmodule ChessDuelBackendWeb.OAuthControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackendWeb.AuthController

  setup do
    previous_id = System.get_env("GOOGLE_CLIENT_ID")
    previous_secret = System.get_env("GOOGLE_CLIENT_SECRET")
    System.put_env("GOOGLE_CLIENT_ID", "test-client-id")
    System.put_env("GOOGLE_CLIENT_SECRET", "test-client-secret")

    on_exit(fn ->
      restore_env("GOOGLE_CLIENT_ID", previous_id)
      restore_env("GOOGLE_CLIENT_SECRET", previous_secret)
    end)
  end

  test "rota Google inicia OAuth e grava state de protecao CSRF", %{conn: conn} do
    response = get(conn, "/auth/google")

    assert redirected_to(response, 302) =~ "https://accounts.google.com/o/oauth2/v2/auth"
    assert redirected_to(response, 302) =~ "state="

    assert Enum.any?(get_resp_header(response, "set-cookie"), fn cookie ->
             String.contains?(cookie, "ueberauth.state_param=")
           end)
  end

  test "rota OAuth volta ao frontend quando as credenciais nao foram configuradas", %{conn: conn} do
    System.delete_env("GOOGLE_CLIENT_ID")
    System.delete_env("GOOGLE_CLIENT_SECRET")

    response = get(conn, "/auth/google")

    assert redirected_to(response, 302) ==
             "http://localhost:3000/?oauth_error=oauth_not_configured"
  end

  test "callback cria sessao API e redireciona o token no fragmento", %{conn: conn} do
    auth = %Ueberauth.Auth{
      provider: :google,
      uid: "google-controller",
      info: %Ueberauth.Auth.Info{
        email: "controller@example.com",
        name: "Controller Player",
        image: "https://images.example.com/controller.png"
      }
    }

    response =
      conn
      |> Plug.Conn.assign(:ueberauth_auth, auth)
      |> AuthController.callback(%{})

    assert redirected_to(response, 302) =~ "http://localhost:3000/auth/callback#token="

    [_, encoded_token] = String.split(redirected_to(response, 302), "#token=", parts: 2)
    token = URI.decode_www_form(encoded_token)

    assert {user, _inserted_at} = Accounts.get_user_by_api_token(token)
    assert user.email == "controller@example.com"
    assert user.google_id == "google-controller"
  end

  test "falha OAuth retorna ao login sem emitir token", %{conn: conn} do
    response =
      conn
      |> Plug.Conn.assign(:ueberauth_failure, %Ueberauth.Failure{})
      |> AuthController.callback(%{})

    assert redirected_to(response, 302) ==
             "http://localhost:3000/?oauth_error=authorization_failed"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
