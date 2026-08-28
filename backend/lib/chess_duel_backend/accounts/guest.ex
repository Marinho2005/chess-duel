defmodule ChessDuelBackend.Accounts.Guest do
  @moduledoc "Identidade temporaria assinada, sem registro na tabela users."

  alias ChessDuelBackendWeb.Endpoint

  @token_prefix "guest:"
  @token_salt "guest session"
  @max_age_seconds 4 * 60 * 60

  def new do
    id = Ecto.UUID.generate()

    guest = %{
      id: "guest-#{id}",
      nickname: "Convidado-#{String.slice(id, 0, 6) |> String.upcase()}",
      guest: true
    }

    token = @token_prefix <> Phoenix.Token.sign(Endpoint, @token_salt, guest)
    %{token: token, guest: guest, expires_in: @max_age_seconds}
  end

  def verify(@token_prefix <> signed_token) do
    case Phoenix.Token.verify(Endpoint, @token_salt, signed_token, max_age: @max_age_seconds) do
      {:ok, %{id: "guest-" <> _, nickname: nickname, guest: true} = guest}
      when is_binary(nickname) ->
        {:ok, guest}

      _ ->
        :error
    end
  end

  def verify(_token), do: :error
  def token?(@token_prefix <> _token), do: true
  def token?(_token), do: false
end
