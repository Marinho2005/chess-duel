defmodule ChessDuelBackendWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :chess_duel_backend

  # CORS: aplicado primeiro para responder a preflight OPTIONS que
  # chegam antes do roteador.
  plug ChessDuelBackendWeb.Plugs.RuntimeCors

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

  socket "/spectator_socket", ChessDuelBackendWeb.SpectatorSocket,
    websocket: true,
    longpoll: false

  plug ChessDuelBackendWeb.Plugs.UploadStatic

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug ChessDuelBackendWeb.Router

  def public_host, do: config(:url) |> Keyword.fetch!(:host)
end
