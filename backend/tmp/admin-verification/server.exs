endpoint = ChessDuelBackendWeb.Endpoint
config = Application.fetch_env!(:chess_duel_backend, endpoint)
Application.put_env(:chess_duel_backend, endpoint, Keyword.merge(config, server: true, http: [ip: {127, 0, 0, 1}, port: 4002]))
Application.put_env(:chess_duel_backend, :cors, origin: ["http://localhost:3001"])
Code.compile_file("lib/chess_duel_backend_web/endpoint.ex")
{:ok, _} = Application.ensure_all_started(:chess_duel_backend)
owner = Ecto.Adapters.SQL.Sandbox.start_owner!(ChessDuelBackend.Repo, shared: true, ownership_timeout: 3_600_000)
alias ChessDuelBackend.{Accounts, Games, Repo}
alias ChessDuelBackend.Accounts.User
create = fn nickname, role ->
  {:ok, user} = Accounts.register_user(%{email: "#{nickname}@example.test", nickname: nickname, password: "BrowserCheck123!"})
  user |> User.confirm_changeset() |> Ecto.Changeset.put_change(:role, role) |> Repo.update!()
end
admin = create.("browser_admin", :admin)
user = create.("browser_player", :user)
{:ok, _} = Games.create_game(%{game_id: "browser-game", white_player_id: user.id, black_player_id: admin.id, status: "finished", result: "draw", end_reason: "draw", finished_at: DateTime.utc_now() |> DateTime.truncate(:second), final_fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"})
IO.puts("BROWSER_CHECK_READY")
receive do
  :stop -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
after
  3_600_000 -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
end
