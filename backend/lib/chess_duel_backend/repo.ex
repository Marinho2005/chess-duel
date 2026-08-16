defmodule ChessDuelBackend.Repo do
  use Ecto.Repo,
    otp_app: :chess_duel_backend,
    adapter: Ecto.Adapters.Postgres
end
