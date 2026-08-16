import Config

config :chess_duel_backend, ecto_repos: [ChessDuelBackend.Repo]

# Configuracao do endpoint
config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: ChessDuelBackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ChessDuelBackend.PubSub,
  live_view: false

# Configuracoes de log
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configuracao de Phoenix
config :phoenix, :json_library, Jason

config :chess_duel_backend, :cors,
  origin: ["http://localhost:3000"],
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  headers: ["Content-Type", "Authorization"]

import_config "#{config_env()}.exs"
