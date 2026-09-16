import Config

if config_env() != :test do
  config :chess_duel_backend, :stockfish, path: System.get_env("STOCKFISH_PATH")
end

if config_env() == :prod do
  required = fn name ->
    case System.get_env(name) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: raise("#{name} must not be empty"), else: value

      _ ->
        raise "#{name} is required in production"
    end
  end

  positive_integer = fn name, default ->
    case Integer.parse(System.get_env(name, default)) do
      {value, ""} when value > 0 -> value
      _ -> raise "#{name} must be a positive integer"
    end
  end

  origin = fn value ->
    uri = URI.parse(value)

    unless uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
             uri.userinfo == nil and uri.path in [nil, ""] and uri.query == nil and
             uri.fragment == nil and not String.contains?(value, "*") do
      raise "Production origins must be explicit HTTPS origins without paths"
    end

    value
  end

  host = required.("PHX_HOST")

  unless Regex.match?(~r/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/, host),
    do: raise("PHX_HOST must contain only a hostname, without scheme or port")

  frontend_url = required.("FRONTEND_URL") |> String.trim_trailing("/") |> origin.()

  origins =
    required.("ALLOWED_ORIGINS")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(origin)
    |> Enum.uniq()

  unless frontend_url in origins, do: raise("ALLOWED_ORIGINS must include FRONTEND_URL")

  database_url = required.("DATABASE_URL")
  database_uri = URI.parse(database_url)

  unless database_uri.scheme in ["postgres", "postgresql", "ecto"] and
           is_binary(database_uri.host) and database_uri.host != "" do
    raise "DATABASE_URL must be a PostgreSQL URL with a hostname"
  end

  query_keys = URI.decode_query(database_uri.query || "") |> Map.keys()

  if Enum.any?(query_keys, &(&1 in ["ssl", "sslmode", "ssl_opts"])),
    do: raise("Configure database TLS only through DATABASE_SSL_MODE, not URL query parameters")

  # Nenhum downgrade automatico: o modo deve corresponder ao endpoint escolhido.
  ssl =
    case required.("DATABASE_SSL_MODE") do
      "disable" ->
        false

      "require" ->
        [verify: :verify_none]

      "verify-full" ->
        [
          verify: :verify_peer,
          cacertfile: required.("DATABASE_CA_CERTFILE"),
          server_name_indication: String.to_charlist(database_uri.host),
          customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
        ]

      _ ->
        raise "DATABASE_SSL_MODE must be disable, require or verify-full"
    end

  config :chess_duel_backend, ChessDuelBackend.Repo,
    url: database_url,
    pool_size: positive_integer.("POOL_SIZE", "10"),
    ssl: ssl

  secret = required.("SECRET_KEY_BASE")
  if byte_size(secret) < 64, do: raise("SECRET_KEY_BASE must have at least 64 bytes")
  port = positive_integer.("PORT", "4000")
  if port > 65_535, do: raise("PORT must not exceed 65535")

  config :chess_duel_backend, :valkey, url: required.("VALKEY_URL")
  config :chess_duel_backend, :cors, origin: origins

  config :chess_duel_backend, ChessDuelBackendWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret,
    server: true,
    check_origin: origins

  upload_dir = required.("UPLOADS_DIR")

  unless Path.type(upload_dir) == :absolute and Path.expand(upload_dir) != "/",
    do: raise("UPLOADS_DIR must be an absolute directory other than root")

  config :chess_duel_backend,
    frontend_url: frontend_url,
    uploads_dir: upload_dir,
    avatar_upload_dir: Path.join(upload_dir, "avatars"),
    club_avatar_upload_dir: Path.join(upload_dir, "clubs")
end

if config_env() != :test do
  config :chess_duel_backend, :lichess_broadcasts, token: System.get_env("LICHESS_API_TOKEN")
end

if config_env() != :prod do
  config :chess_duel_backend,
         :frontend_url,
         System.get_env("FRONTEND_URL", "http://localhost:3000")
end

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
