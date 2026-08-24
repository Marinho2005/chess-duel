import Config

config :chess_duel_backend,
       :frontend_url,
       System.get_env("FRONTEND_URL", "http://localhost:3000")

# Only in production and test, you can configure these.
# For production, real secret key base must be present.
if System.get_env("SECRET_KEY_BASE") do
  config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
    secret_key_base: System.get_env("SECRET_KEY_BASE")
end
