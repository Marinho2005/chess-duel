defmodule ChessDuelBackend.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ChessDuelBackend.Repo,
        {Phoenix.PubSub, name: ChessDuelBackend.PubSub},
        ChessDuelBackend.ChessValidator,
        ChessDuelBackend.Games.Lobby,
        {Registry, keys: :unique, name: ChessDuelBackend.GameRegistry},
        {DynamicSupervisor, name: ChessDuelBackend.GameSupervisor, strategy: :one_for_one},
        redix_child_spec(),
        ChessDuelBackend.Games.Matchmaker,
        ChessDuelBackendWeb.Endpoint
      ]

    opts = [strategy: :one_for_one, name: ChessDuelBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Redix 1.6+ nao aceita a opcao :url; exige host/port (e opcionalmente
  # password) separados. Fazemos o parse de VALKEY_URL (ou VALKEY_HOST/
  # VALKEY_PORT) e montamos a child spec com host e port explicitos.
  defp redix_child_spec do
    valkey_config = Application.get_env(:chess_duel_backend, :valkey, [])
    url = Keyword.get(valkey_config, :url)

    opts =
      if is_binary(url) and String.trim(url) != "" do
        uri = URI.parse(url)
        base = [host: uri.host, port: uri.port]

        case uri.userinfo do
          nil ->
            base

          "" ->
            base

          userinfo ->
            # Redix nao usa username; se houver "user:pass" ou so ":pass",
            # extraimos apenas a senha.
            password =
              case String.split(userinfo, ":", parts: 2) do
                [_, pass] -> pass
                [pass] -> pass
              end

            Keyword.put(base, :password, password)
        end
      else
        [
          host: System.get_env("VALKEY_HOST", "localhost"),
          port: String.to_integer(System.get_env("VALKEY_PORT", "6379"))
        ]
      end

    opts = Keyword.put(opts, :name, :valkey)
    {Redix, opts}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ChessDuelBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
