import Config

# Configure your database
database_url =
  case System.get_env("DATABASE_URL") do
    value when is_binary(value) and value != "" ->
      value

    _ ->
      "ecto://#{System.get_env("DB_USER", "chess_duel")}:#{System.get_env("DB_PASSWORD", "chess_duel_password")}@#{System.get_env("DB_HOST", "localhost")}:#{System.get_env("DB_PORT", "5432")}/#{System.get_env("DB_NAME", "chess_duel_dev")}"
  end

config :chess_duel_backend, ChessDuelBackend.Repo,
  url: database_url,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Valkey (compativel com Redis)
valkey_url = System.get_env("VALKEY_URL", "redis://localhost:6379")
config :chess_duel_backend, :valkey, url: valkey_url

# Endpoint de desenvolvimento (API only: sem code_reloader/assets).
config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  debug_errors: true,
  secret_key_base:
    "dZ0K1n2g3o4k5s6e7g8r9e0t1k2e3y4b5a6s7e8d9e0v1o2n3l4y5d6o7n8o9t0u1s2e3i4n5p6r7o8d"

# Set a higher stacktrace during development.
config :logger, :console, format: "[$level] $message\n"

# Initialize plugs at runtime for faster development compilation.
config :phoenix, :plug_init_mode, :runtime

# Set a higher stacktrace during development.
config :phoenix, :stacktrace_depth, 20
