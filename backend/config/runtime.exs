import Config

if config_env() != :test do
  config :chess_duel_backend, :lichess_broadcasts, token: System.get_env("LICHESS_API_TOKEN")
end

config :chess_duel_backend,
       :frontend_url,
       System.get_env("FRONTEND_URL", "http://localhost:3000")

# Estas strategies esperam strings na configuracao. O runtime config mantem os
# secrets fora do codigo e os le somente quando a aplicacao inicia.
config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

# Only in production and test, you can configure these.
# For production, real secret key base must be present.
if System.get_env("SECRET_KEY_BASE") do
  config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
    secret_key_base: System.get_env("SECRET_KEY_BASE")
end
