defmodule ChessDuelBackend.Games.BotsTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.GameAnalysis.Stockfish
  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games.{BotGames, Bots, GameServer, TimeControl}
  alias ChessDuelBackend.Ratings

  test "catálogo oferece os cinco bots e todos podem criar uma partida" do
    user = register_user("catalog")

    assert Enum.map(Bots.all(), & &1.id) == ~w(clark jonathan renan boris terminator)

    for bot <- Bots.all() do
      assert {:ok, game} = BotGames.create(user.id, bot.id, "blitz_3_0", "white")
      assert game.bot.id == bot.id
      cleanup(game.game_id)
    end
  end

  test "Stockfish recebe FEN e retorna um lance legal no formato UCI" do
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    assert {:ok, move} = Stockfish.best_move(fen, skill_level: 0, movetime_ms: 30)
    assert move =~ ~r/^[a-h][1-8][a-h][1-8][qrbn]?$/
  end

  test "bot calcula, aplica e publica seu lance no tópico da partida" do
    user = register_user("broadcast")
    bot = Bots.get("clark")
    {:ok, control} = TimeControl.fetch("blitz_3_0")
    game_id = Ecto.UUID.generate()
    topic = "game:#{game_id}"
    ChessDuelBackendWeb.Endpoint.subscribe(topic)

    assert {:ok, _} = GameServer.reserve_bot_game(game_id, user.id, bot, "black", control)

    assert_receive %Phoenix.Socket.Broadcast{
                     topic: ^topic,
                     event: "move_made",
                     payload: %{player: "bot:clark", new_fen: new_fen}
                   },
                   5_000

    refute new_fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    assert {:ok, state} = GameServer.get_state(game_id)
    assert length(state.moves) == 1
    assert state.current_turn == "black"
    cleanup(game_id)
  end

  test "posição e token impedem dois lances do bot" do
    previous = Application.get_env(:chess_duel_backend, :stockfish)
    Application.put_env(:chess_duel_backend, :stockfish, Keyword.put(previous, :path, "/missing"))
    on_exit(fn -> Application.put_env(:chess_duel_backend, :stockfish, previous) end)

    user = register_user("move")
    bot = Bots.get("clark")
    {:ok, control} = TimeControl.fetch("blitz_3_0")
    game_id = Ecto.UUID.generate()
    assert {:ok, _} = GameServer.reserve_bot_game(game_id, user.id, bot, "white", control)
    assert {:ok, waiting_bot} = GameServer.make_move(game_id, "e2", "e4", user.id)
    token = waiting_bot.bot_request

    assert {:ok, after_bot} =
             GameServer.apply_bot_move(game_id, waiting_bot.fen, token, "e7", "e5", nil)

    assert length(after_bot.moves) == 2

    assert {:error, :stale_bot_move} =
             GameServer.apply_bot_move(game_id, waiting_bot.fen, token, "e7", "e5", nil)

    cleanup(game_id)
  end

  test "partida contra bot nunca é ranqueada" do
    user = register_user("rating")
    {:ok, game} = BotGames.create(user.id, "clark", "blitz_3_0", "white")
    persisted = ChessDuelBackend.Games.get_game_by_game_id(game.game_id)

    {:ok, persisted} =
      ChessDuelBackend.Games.update_game(persisted, %{
        status: "finished",
        result: "white_wins",
        end_reason: "resignation",
        finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    assert {:error, :game_not_rateable} = Ratings.rate_game(persisted.game_id)
    cleanup(game.game_id)
  end

  defp cleanup(game_id) do
    case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
      [] -> :ok
    end
  end

  defp register_user(prefix) do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        email: "#{prefix}-#{unique}@example.com",
        nickname: "#{prefix}_#{unique}",
        password: "password1234"
      })

    user
  end
end
