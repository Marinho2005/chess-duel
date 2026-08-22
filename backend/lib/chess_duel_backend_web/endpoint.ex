defmodule ChessDuelBackendWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :chess_duel_backend

  # CORS: aplicado primeiro para responder a preflight OPTIONS que
  # chegam antes do roteador.
  plug CORSPlug, Application.get_env(:chess_duel_backend, :cors, [])

  # The session will be stored in the cookie and signed
  # (this is only kept for compatibility; we don't use it for now).
  @session_options [
    store: :cookie,
    key: "_chess_duel_backend_key",
    signing_salt: "chess_duel"
  ]

  socket "/socket", ChessDuelBackendWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/uploads",
    from: {:chess_duel_backend, "priv/static/uploads"},
    gzip: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head

  plug ChessDuelBackendWeb.Router
end
