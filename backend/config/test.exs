import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
database_url =
  System.get_env("DATABASE_URL") ||
    "ecto://#{System.get_env("DB_USER", "chess_duel")}:#{System.get_env("DB_PASSWORD", "chess_duel_password")}@#{System.get_env("DB_HOST", "localhost")}:#{System.get_env("DB_PORT", "5432")}/chess_duel_test#{System.get_env("MIX_TEST_PARTITION")}"

config :chess_duel_backend, ChessDuelBackend.Repo,
  url: database_url,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

valkey_url = System.get_env("VALKEY_URL", "redis://localhost:6379")
config :chess_duel_backend, :valkey, url: valkey_url

# We don't run a server during test. If one is required, you can enable it.
config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "t1e2s3t4s5e6c7r8e9t0k1e2y3b4a5s6e7d8e9v0o1n2l3y4d5o6n7o8t9u0s1e2i3n4p5r6o7d8",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
