import Config

# Somente configuracao de compilacao; nenhum segredo ou endereco entra na imagem.
config :logger, level: :info

# force_ssl e instalado em compile-time, mas o host e resolvido em runtime.
# Somente o proxy confiavel deve acessar a porta HTTP da aplicacao.
config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    host: {ChessDuelBackendWeb.Endpoint, :public_host, []},
    exclude: [paths: ["/api/health"]],
    log: false
  ]
