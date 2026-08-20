import Config

# For production, you'll want to configure these. All vars are read from env.

database_url =
  System.get_env("DATABASE_URL") ||
    "ecto://#{System.get_env("DB_USER", "chess_duel")}:#{System.get_env("DB_PASSWORD", "chess_duel_password")}@#{System.get_env("DB_HOST", "localhost")}:#{System.get_env("DB_PORT", "5432")}/#{System.get_env("DB_NAME", "chess_duel_prod")}"

config :chess_duel_backend, ChessDuelBackend.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

valkey_url = System.get_env("VALKEY_URL", "redis://localhost:6379")
config :chess_duel_backend, :valkey, url: valkey_url

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: System.get_env("PORT", "4000")],
  secret_key_base: secret_key_base,
  server: true,
  check_origin:
    System.get_env("ALLOWED_ORIGINS", "http://localhost:3000") |> String.split(",", trim: true)

if System.get_env("PHX_SERVER") do
  config :chess_duel_backend, ChessDuelBackendWeb.Endpoint, server: true
end
