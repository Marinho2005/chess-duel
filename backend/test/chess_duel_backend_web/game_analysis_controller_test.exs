defmodule ChessDuelBackendWeb.GameAnalysisControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: true
  use Oban.Testing, repo: ChessDuelBackend.Repo

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.GameAnalysis.Job
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Repo

  test "participante solicita uma análise idempotente e consulta seu estado", %{conn: conn} do
    user = confirmed_user!("analysis@example.com", "analysis_player")
    opponent = confirmed_user!("analysis-opponent@example.com", "analysis_opponent")
    game = finished_game!(user.id, opponent.id)
    conn = authenticate(conn, user)

    response = conn |> post("/api/games/#{game.id}/analyze") |> json_response(202)
    assert response["status"] == "pending"
    assert response["game"]["viewer_color"] == "white"
    assert response["game"]["moves"] == [%{"from" => "e2", "to" => "e4"}]
    assert_enqueued(worker: Job, args: %{analysis_id: response["id"]})

    repeated = conn |> recycle() |> post("/api/games/#{game.id}/analyze") |> json_response(202)
    assert repeated["id"] == response["id"]

    queried = conn |> recycle() |> get("/api/games/#{game.id}/analysis") |> json_response(200)
    assert queried["id"] == response["id"]
  end

  test "impede acesso de quem não participa e a partidas não finalizadas", %{conn: conn} do
    user = confirmed_user!("owner@example.com", "analysis_owner")
    opponent = confirmed_user!("opponent2@example.com", "analysis_opponent_2")
    outsider = confirmed_user!("outside@example.com", "analysis_outsider")
    game = finished_game!(user.id, opponent.id)

    assert %{"error" => "Você não participa desta partida."} =
             conn
             |> authenticate(outsider)
             |> post("/api/games/#{game.id}/analyze")
             |> json_response(403)

    {:ok, unfinished} =
      Games.create_game(%{
        game_id: "unfinished-analysis",
        status: "in_progress",
        white_player_id: user.id,
        black_player_id: opponent.id
      })

    assert %{"error" => "A partida precisa estar finalizada."} =
             conn
             |> authenticate(user)
             |> post("/api/games/#{unfinished.id}/analyze")
             |> json_response(422)
  end

  defp authenticate(conn, user) do
    put_req_header(conn, "authorization", "Bearer #{Accounts.generate_user_api_token(user)}")
  end

  defp confirmed_user!(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user |> User.confirm_changeset() |> Repo.update!()
  end

  defp finished_game!(white_id, black_id) do
    {:ok, game} =
      Games.create_game(%{
        game_id: "analysis-#{System.unique_integer([:positive])}",
        status: "finished",
        white_player_id: white_id,
        black_player_id: black_id,
        moves: [%{"from" => "e2", "to" => "e4"}],
        result: "white_wins",
        end_reason: "checkmate",
        finished_at: DateTime.utc_now()
      })

    game
  end
end
