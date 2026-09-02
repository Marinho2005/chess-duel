defmodule ChessDuelBackend.Puzzles.BattleTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Puzzles.BattleRatingChange
  alias ChessDuelBackend.Puzzles.{BattleServer, Puzzle}

  setup do
    player_one = user!("battle-one@example.com", "battle_one")
    player_two = user!("battle-two@example.com", "battle_two")

    for index <- 0..7 do
      puzzle!(index)
    end

    %{player_one: player_one, player_two: player_two}
  end

  test "usa sequência idêntica, progresso independente e rating Battle idempotente", context do
    assert {:ok, battle_id} = BattleServer.create(context.player_one, context.player_two, 180)
    assert {:ok, one} = BattleServer.snapshot(battle_id, context.player_one.id)
    assert {:ok, two} = BattleServer.snapshot(battle_id, context.player_two.id)
    assert one.puzzle.id == two.puzzle.id
    assert one.ends_at == two.ends_at

    assert {:ok, partial} =
             BattleServer.attempt(battle_id, context.player_one.id, 1, "h1h2")

    assert partial.automatic_move == "a2a3"

    assert {:ok, solved} =
             BattleServer.attempt(battle_id, context.player_one.id, 3, "h2h3")

    assert solved.resolved
    assert solved.progress[context.player_one.id].score == 1
    assert solved.progress[context.player_two.id].score == 0

    assert {:ok, missed} =
             BattleServer.attempt(battle_id, context.player_two.id, 1, "a8a7")

    assert missed.status == :incorrect
    assert missed.progress[context.player_two.id].errors == 1

    [{pid, _}] = Registry.lookup(ChessDuelBackend.PuzzleBattleRegistry, battle_id)
    send(pid, :expire)
    Process.sleep(30)

    assert {:ok, finished} = BattleServer.snapshot(battle_id, context.player_one.id)
    assert finished.status == :finished
    assert finished.result.result == "player_one_wins"
    assert finished.result.winner_id == context.player_one.id

    one = Repo.get!(User, context.player_one.id)
    two = Repo.get!(User, context.player_two.id)
    assert one.battle_rating == 1216
    assert two.battle_rating == 1184
    assert one.rating == 1200 and one.puzzle_rating == 1200
    assert two.rating == 1200 and two.puzzle_rating == 1200

    send(pid, :expire)
    Process.sleep(20)
    assert Repo.aggregate(BattleRatingChange, :count) == 2

    DynamicSupervisor.terminate_child(ChessDuelBackend.PuzzleBattleSupervisor, pid)
  end

  test "desempata por menos erros e permite empate determinístico", _context do
    assert ChessDuelBackend.Puzzles.Battles.result_for(
             %{score: 8, errors: 1},
             %{score: 8, errors: 2}
           ) == "player_one_wins"

    assert ChessDuelBackend.Puzzles.Battles.result_for(
             %{score: 8, errors: 2},
             %{score: 8, errors: 2}
           ) == "draw"
  end

  defp user!(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user |> User.confirm_changeset() |> Repo.update!()
  end

  defp puzzle!(index) do
    %Puzzle{}
    |> Puzzle.changeset(%{
      lichess_id: "battle-test-#{index}-#{System.unique_integer([:positive])}",
      fen: "8/8/8/8/8/8/8/K6k w - - 0 1",
      moves: ["a1a2", "h1h2", "a2a3", "h2h3"],
      rating: 800 + index * 100,
      themes: ["battle"],
      popularity: 100
    })
    |> Repo.insert!()
  end
end
