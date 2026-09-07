defmodule ChessDuelBackendWeb.GameHistoryControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: true

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Ratings.RatingChange
  alias ChessDuelBackend.Repo

  test "lista somente partidas finalizadas do usuario, por data e com paginacao", %{conn: conn} do
    user = confirmed_user!("history@example.com", "history_player")
    opponent = confirmed_user!("opponent@example.com", "opponent_player")
    outsider = confirmed_user!("outsider@example.com", "outsider_player")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    oldest =
      finished_game!(user.id, opponent.id, "white_wins", "checkmate", DateTime.add(now, -30))

    middle =
      finished_game!(user.id, opponent.id, "black_wins", "timeout", DateTime.add(now, -20))

    newest =
      finished_game!(opponent.id, user.id, "draw", "stalemate", DateTime.add(now, -10))

    rating_change!(oldest, user, 12)
    rating_change!(middle, user, -9)
    rating_change!(newest, user, 0)

    finished_game!(opponent.id, outsider.id, "white_wins", "checkmate", now)

    {:ok, _unfinished} =
      Games.create_game(%{
        game_id: "unfinished-#{System.unique_integer([:positive])}",
        status: "in_progress",
        white_player_id: user.id,
        black_player_id: opponent.id
      })

    token = Accounts.generate_user_api_token(user)
    authenticated_conn = put_req_header(conn, "authorization", "Bearer #{token}")

    response =
      authenticated_conn
      |> get("/api/users/me/games?page=1&per_page=2")
      |> json_response(200)

    assert response["pagination"] == %{
             "page" => 1,
             "per_page" => 2,
             "total" => 3,
             "total_pages" => 2,
             "has_more" => true
           }

    assert [newest_item, middle_item] = response["games"]
    assert newest_item["id"] == newest.id
    assert newest_item["opponent"]["nickname"] == "opponent_player"
    assert newest_item["color"] == "black"
    assert newest_item["result"] == "draw"
    assert newest_item["end_reason"] == "stalemate"
    assert newest_item["rating_change"] == 0
    assert newest_item["time_control"]["label"] == "Blitz 3+0"

    assert middle_item["id"] == middle.id
    assert middle_item["result"] == "loss"
    assert middle_item["rating_change"] == -9

    second_page =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/users/me/games?page=2&per_page=2")
      |> json_response(200)

    assert [%{"id" => oldest_id, "result" => "win", "rating_change" => 12}] =
             second_page["games"]

    assert oldest_id == oldest.id
    refute second_page["pagination"]["has_more"]
  end

  test "historico exige autenticacao", %{conn: conn} do
    assert %{"error" => "authentication_required"} =
             conn
             |> get("/api/users/me/games")
             |> json_response(401)
  end

  test "filtra o historico e a paginacao pela categoria", %{conn: conn} do
    user = confirmed_user!("category-history@example.com", "category_history")
    opponent = confirmed_user!("category-opponent@example.com", "category_opponent")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    bullet =
      finished_game!(user.id, opponent.id, "white_wins", "checkmate", now, %{
        initial_time_ms: 60_000,
        increment_ms: 0
      })

    rating_change!(bullet, user, 14, :bullet)

    finished_game!(user.id, opponent.id, "black_wins", "timeout", DateTime.add(now, -10), %{
      initial_time_ms: 600_000,
      increment_ms: 0
    })

    token = Accounts.generate_user_api_token(user)

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/users/me/games?category=bullet&per_page=5")
      |> json_response(200)

    assert response["pagination"]["total"] == 1
    assert [%{"id" => game_id, "time_control" => %{"id" => "bullet_1_0"}}] = response["games"]
    assert game_id == bullet.id

    assert [
             %{
               "category" => "bullet",
               "rating_before" => 1200,
               "rating_after" => 1214
             }
           ] = response["rating_history"]
  end

  defp confirmed_user!(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  defp finished_game!(white_id, black_id, result, end_reason, finished_at, extra_attrs \\ %{}) do
    {:ok, game} =
      %{
        game_id: "history-game-#{System.unique_integer([:positive])}",
        status: "finished",
        white_player_id: white_id,
        black_player_id: black_id,
        result: result,
        end_reason: end_reason,
        finished_at: finished_at
      }
      |> Map.merge(extra_attrs)
      |> Games.create_game()

    game
  end

  defp rating_change!(game, user, change, category \\ :blitz) do
    %RatingChange{}
    |> RatingChange.changeset(%{
      game_id: game.id,
      user_id: user.id,
      rating_before: 1200,
      rating_after: 1200 + change,
      change: change,
      category: category
    })
    |> Repo.insert!()
  end
end
