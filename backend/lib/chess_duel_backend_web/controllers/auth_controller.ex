defmodule ChessDuelBackendWeb.AuthController do
  use ChessDuelBackendWeb, :controller

  plug :ensure_provider_configured
  plug Ueberauth, providers: [:google, :discord, :github]

  alias ChessDuelBackend.Accounts

  # O plug Ueberauth intercepta as rotas conhecidas antes destas actions.
  def request(conn, _params), do: oauth_error(conn, "unsupported_provider")

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    oauth_error(conn, "authorization_failed")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    with {:ok, provider} <- provider_atom(auth.provider),
         {:ok, user} <-
           Accounts.authenticate_oauth_user(provider, %{
             uid: auth.uid,
             email: auth.info.email,
             nickname: auth.info.nickname,
             name: auth.info.name,
             avatar_url: auth.info.image,
             email_verified: email_verified?(auth)
           }),
         :ok <- oauth_account_access(user) do
      token = Accounts.generate_user_api_token(user)
      redirect(conn, external: frontend_callback_url(token))
    else
      {:error, reason} -> oauth_error(conn, reason)
    end
  end

  def callback(conn, _params), do: oauth_error(conn, "invalid_oauth_callback")

  defp oauth_account_access(user) do
    case ChessDuelBackend.Accounts.AccountAccess.check(user) do
      :ok -> :ok
      {:error, %{error: code}} -> {:error, code}
    end
  end

  defp ensure_provider_configured(conn, _options) do
    provider = conn.params["provider"]

    if provider_configured?(provider) do
      conn
    else
      conn
      |> oauth_error("oauth_not_configured")
      |> halt()
    end
  end

  defp provider_configured?("google") do
    present_env?("GOOGLE_CLIENT_ID") and present_env?("GOOGLE_CLIENT_SECRET")
  end

  defp provider_configured?("discord") do
    present_env?("DISCORD_CLIENT_ID") and present_env?("DISCORD_CLIENT_SECRET")
  end

  defp provider_configured?("github") do
    present_env?("GITHUB_CLIENT_ID") and present_env?("GITHUB_CLIENT_SECRET")
  end

  defp provider_configured?(_provider), do: false

  defp present_env?(name) do
    case System.get_env(name) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end

  defp provider_atom(provider) when provider in [:google, "google"], do: {:ok, :google}
  defp provider_atom(provider) when provider in [:discord, "discord"], do: {:ok, :discord}
  defp provider_atom(provider) when provider in [:github, "github"], do: {:ok, :github}
  defp provider_atom(_provider), do: {:error, :unsupported_provider}

  # O Google inclui este atributo no perfil validado pela strategy. Os demais
  # provedores nunca usam email para vinculacao automatica.
  defp email_verified?(%{provider: provider} = auth) when provider in [:google, "google"] do
    raw_info = auth.extra && auth.extra.raw_info
    user = raw_info && (raw_info[:user] || raw_info["user"])
    value = user && (user[:email_verified] || user["email_verified"])
    value in [true, "true"]
  end

  defp email_verified?(_auth), do: false

  # O fragmento nao e enviado em requests HTTP nem no header Referer. Assim o
  # bearer token chega somente ao JavaScript da pagina de callback do Nuxt.
  defp frontend_callback_url(token) do
    "#{frontend_url()}/auth/callback#token=#{URI.encode_www_form(token)}"
  end

  defp oauth_error(conn, reason) do
    message = reason |> oauth_error_code() |> URI.encode_www_form()
    redirect(conn, external: "#{frontend_url()}/?oauth_error=#{message}")
  end

  defp oauth_error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp oauth_error_code(reason) when is_binary(reason), do: reason
  defp oauth_error_code(_reason), do: "oauth_account_error"

  defp frontend_url do
    :chess_duel_backend
    |> Application.fetch_env!(:frontend_url)
    |> String.trim_trailing("/")
  end
end
