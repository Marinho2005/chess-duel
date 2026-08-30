defmodule ChessDuelBackendWeb.OAuthControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.OAuthIdentity
  alias ChessDuelBackend.Repo
  alias ChessDuelBackendWeb.AuthController

  setup do
    names =
      ~w(GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET)

    previous = Map.new(names, &{&1, System.get_env(&1)})
    oauth_modules = [Ueberauth.Strategy.Discord.OAuth, Ueberauth.Strategy.Github.OAuth]
    previous_oauth_config = Map.new(oauth_modules, &{&1, Application.get_env(:ueberauth, &1)})
    Enum.each(names, &System.put_env(&1, "test-value"))

    Enum.each(oauth_modules, fn module ->
      Application.put_env(:ueberauth, module,
        client_id: "test-client-id",
        client_secret: "test-client-secret"
      )
    end)

    on_exit(fn ->
      Enum.each(previous, fn {name, value} -> restore_env(name, value) end)

      Enum.each(previous_oauth_config, fn
        {module, nil} -> Application.delete_env(:ueberauth, module)
        {module, config} -> Application.put_env(:ueberauth, module, config)
      end)
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

  for {provider, authorize_host} <- [discord: "discord.com", github: "github.com"] do
    test "rota #{provider} inicia OAuth e grava state de protecao CSRF", %{conn: conn} do
      response = get(conn, "/auth/#{unquote(provider)}")

      assert redirected_to(response, 302) =~ unquote(authorize_host)
      assert redirected_to(response, 302) =~ "state="

      assert Enum.any?(get_resp_header(response, "set-cookie"), fn cookie ->
               String.contains?(cookie, "ueberauth.state_param=")
             end)
    end
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
      },
      extra: %Ueberauth.Auth.Extra{raw_info: %{user: %{"email_verified" => true}}}
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

    assert Repo.get_by!(OAuthIdentity, user_id: user.id, provider: "google").provider_uid ==
             "google-controller"
  end

  for provider <- [:discord, :github] do
    test "callback #{provider} cria sessao com a identidade do provedor", %{conn: conn} do
      provider = unquote(provider)

      auth = %Ueberauth.Auth{
        provider: provider,
        uid: "#{provider}-controller",
        info: %Ueberauth.Auth.Info{
          email: "#{provider}-controller@example.com",
          nickname: "#{provider}_controller"
        }
      }

      response =
        conn
        |> Plug.Conn.assign(:ueberauth_auth, auth)
        |> AuthController.callback(%{})

      assert redirected_to(response, 302) =~ "http://localhost:3000/auth/callback#token="
      identity = Repo.get_by!(OAuthIdentity, provider: Atom.to_string(provider))
      assert identity.provider_uid == "#{provider}-controller"
    end
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
