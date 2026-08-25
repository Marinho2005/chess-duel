import Config

config :chess_duel_backend, :scopes,
  user: [
    default: true,
    module: ChessDuelBackend.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: ChessDuelBackend.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

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

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]

# As credenciais sao criadas manualmente no Google Cloud Console.
# As tuplas fazem a leitura somente em runtime.
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {System, :get_env, ["GOOGLE_CLIENT_ID"]},
  client_secret: {System, :get_env, ["GOOGLE_CLIENT_SECRET"]}

import_config "#{config_env()}.exs"
