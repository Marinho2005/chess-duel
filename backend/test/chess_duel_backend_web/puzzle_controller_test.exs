defmodule ChessDuelBackendWeb.PuzzleControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Puzzles.{Attempt, Puzzle, RushScore}
  alias ChessDuelBackend.Repo

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.register_user(%{
        email: "puzzle-#{System.unique_integer([:positive])}@example.com",
        nickname: "puzzle_#{System.unique_integer([:positive])}",
        password: "password1234"
      })

    user = user |> User.confirm_changeset() |> Repo.update!()
    puzzle = puzzle!()
    conn = put_req_header(conn, "authorization", "Bearer #{Accounts.generate_user_api_token(user)}")
    %{conn: conn, user: user, puzzle: puzzle}
  end

  test "entrega setup separado e avança uma solução com respostas automáticas", context do
    response = context.conn |> get("/api/puzzles/next") |> json_response(200)
    assert response["puzzle"]["id"] == context.puzzle.id
    assert response["puzzle"]["setup_move"] == "a1a2"
    assert response["puzzle"]["expected_index"] == 1
    refute Map.has_key?(response["puzzle"], "moves")

    partial =
      context.conn
      |> recycle()
      |> post("/api/puzzles/#{context.puzzle.id}/attempt", %{
        from: "h1",
        to: "h2",
        index: 1
      })
      |> json_response(200)

    assert partial == %{
             "automatic_move" => "a2a3",
             "next_index" => 3,
             "resolved" => false,
             "status" => "correct"
           }

    solved =
      context.conn
      |> recycle()
      |> post("/api/puzzles/#{context.puzzle.id}/attempt", %{
        from: "h2",
        to: "h3",
        index: 3
      })
      |> json_response(200)

    assert solved["resolved"]
    assert solved["puzzle_rating"] == 1216
    assert solved["rating_before"] == 1200
    assert solved["rating_after"] == 1216
    assert solved["rating_change"] == 16
    assert Repo.get!(User, context.user.id).puzzle_rating == 1216

    assert %Attempt{outcome: "correct", rating_change: 16} =
             attempt = Repo.get_by!(Attempt, user_id: context.user.id, puzzle_id: context.puzzle.id)

    assert attempt.time_spent_ms >= 0
  end

  test "erro não revela resposta e altera o rating apenas uma vez", context do
    context.conn |> get("/api/puzzles/next") |> json_response(200)

    first = wrong_attempt(context.conn, context.puzzle.id)
    assert first["status"] == "incorrect"
    assert first["completed"]
    assert first["rating_before"] == 1200
    assert first["rating_after"] == 1184
    assert first["rating_change"] == -16
    refute Map.has_key?(first, "expected_move")

    context.conn
    |> recycle()
    |> post("/api/puzzles/#{context.puzzle.id}/attempt", %{from: "a8", to: "a7", index: 1})
    |> json_response(409)

    assert Repo.get!(User, context.user.id).puzzle_rating == 1184

    assert Repo.get_by!(Attempt, user_id: context.user.id, puzzle_id: context.puzzle.id).outcome ==
             "incorrect"
  end

  test "Puzzle Rush progride, reconecta, encerra no terceiro erro e não altera ratings", context do
    started =
      context.conn
      |> post("/api/puzzle_rush/start", %{duration_seconds: 180})
      |> json_response(201)

    assert started["puzzle"]["setup_move"] == "a1a2"
    assert started["remaining_ms"] <= 180_000
    assert started["remaining_ms"] > 0
    assert started["errors"] == 0
    assert started["maximum_errors"] == 3

    reconnected =
      context.conn
      |> recycle()
      |> get("/api/puzzle_rush/#{started["session_id"]}")
      |> json_response(200)

    assert reconnected["session_id"] == started["session_id"]
    assert reconnected["ends_at"] == started["ends_at"]

    partial =
      rush_attempt(context.conn, started["session_id"], "h1", "h2", 1)

    assert partial["automatic_move"] == "a2a3"
    assert partial["score"] == 0

    completed =
      rush_attempt(context.conn, started["session_id"], "h2", "h3", 3)

    assert completed["resolved"]
    assert completed["score"] == 1
    assert completed["puzzle"]["setup_move"] == "a1a2"

    first_error = rush_attempt(context.conn, started["session_id"], "a8", "a7", 1)
    assert first_error["errors"] == 1
    refute first_error["finished"]
    second_error = rush_attempt(context.conn, started["session_id"], "a8", "a7", 1)
    assert second_error["errors"] == 2
    result = rush_attempt(context.conn, started["session_id"], "a8", "a7", 1)
    assert result["finished"]
    assert result["score"] == 1
    assert result["errors"] == 3

    assert %RushScore{score: 1, errors: 3, duration_seconds: 180, user_id: user_id} =
             Repo.get_by(RushScore, session_id: started["session_id"])

    assert user_id == context.user.id
    unchanged = Repo.get!(User, context.user.id)
    assert unchanged.rating == 1200
    assert unchanged.puzzle_rating == 1200
    assert unchanged.battle_rating == 1200
  end

  defp wrong_attempt(conn, puzzle_id) do
    conn
    |> recycle()
    |> post("/api/puzzles/#{puzzle_id}/attempt", %{from: "a8", to: "a7", index: 1})
    |> json_response(200)
  end

  defp rush_attempt(conn, session_id, from, to, index) do
    conn
    |> recycle()
    |> post("/api/puzzle_rush/#{session_id}/attempt", %{from: from, to: to, index: index})
    |> json_response(200)
  end

  defp puzzle! do
    %Puzzle{}
    |> Puzzle.changeset(%{
      lichess_id: "test-#{System.unique_integer([:positive])}",
      fen: "8/8/8/8/8/8/8/K6k w - - 0 1",
      moves: ["a1a2", "h1h2", "a2a3", "h2h3"],
      rating: 1200,
      themes: ["mate"],
      popularity: 100
    })
    |> Repo.insert!()
  end
end
