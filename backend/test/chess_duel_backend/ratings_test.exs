defmodule ChessDuelBackend.RatingsTest do
  use ChessDuelBackend.DataCase, async: true

  import Ecto.Query

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Ratings
  alias ChessDuelBackend.Ratings.RatingChange
  alias ChessDuelBackend.Repo

  test "atualiza os dois ratings atomicamente e registra o historico uma unica vez" do
    white = register_user("rating-white@example.com", "rating_white")
    black = register_user("rating-black@example.com", "rating_black")

    {:ok, game} = finished_game(white.id, black.id, "white_wins")

    assert {:ok, rating} = Ratings.rate_game(game.game_id)
    assert rating.white == %{id: white.id, before: 1200, after: 1216}
    assert rating.black == %{id: black.id, before: 1200, after: 1184}

    assert Accounts.get_user!(white.id).blitz_rating == 1216
    assert Accounts.get_user!(black.id).blitz_rating == 1184
    assert Accounts.get_user!(white.id).bullet_rating == 1200
    assert Accounts.get_user!(white.id).rapid_rating == 1200

    rated_game = Games.get_game!(game.id)
    assert rated_game.rated_at
    assert rated_game.white_rating_before == 1200
    assert rated_game.white_rating_after == 1216
    assert rated_game.black_rating_before == 1200
    assert rated_game.black_rating_after == 1184

    assert Repo.aggregate(
             from(change in RatingChange, where: change.game_id == ^game.id),
             :count
           ) == 2

    assert {:ok, :already_rated} = Ratings.rate_game(game.game_id)
    assert Accounts.get_user!(white.id).blitz_rating == 1216
    assert Repo.aggregate(RatingChange, :count) == 2
  end

  test "empate registra movimentacoes sem inventar pontos" do
    white = register_user("draw-white@example.com", "draw_white")
    black = register_user("draw-black@example.com", "draw_black")

    {:ok, game} = finished_game(white.id, black.id, "draw")

    assert {:ok, rating} = Ratings.rate_game(game.game_id)
    assert rating.white.after == 1200
    assert rating.black.after == 1200

    changes = Repo.all(from change in RatingChange, where: change.game_id == ^game.id)
    assert Enum.all?(changes, &(&1.change == 0))
  end

  test "partida abandonada sem vencedor nao altera rating" do
    white = register_user("abandoned-white@example.com", "abandoned_white")
    black = register_user("abandoned-black@example.com", "abandoned_black")

    {:ok, game} = finished_game(white.id, black.id, "abandoned")

    assert {:error, :game_not_rateable} = Ratings.rate_game(game.game_id)
    assert Accounts.get_user!(white.id).blitz_rating == 1200
    assert Accounts.get_user!(black.id).blitz_rating == 1200
    refute Games.get_game!(game.id).rated_at
  end

  test "isola o ELO nas tres modalidades e compartilha blitz 3+0 e 5+0" do
    controls = [
      {:bullet, 60_000, 0},
      {:blitz, 180_000, 0},
      {:blitz, 300_000, 0},
      {:rapid, 600_000, 0}
    ]

    Enum.with_index(controls, fn {category, initial, increment}, index ->
      white = register_user("mode-white-#{index}@example.com", "mode_white_#{index}")
      black = register_user("mode-black-#{index}@example.com", "mode_black_#{index}")
      {:ok, game} = finished_game(white.id, black.id, "white_wins", initial, increment)
      assert {:ok, %{category: ^category}} = Ratings.rate_game(game.game_id)

      updated = Accounts.get_user!(white.id)
      assert ChessDuelBackend.Accounts.User.rating_for(updated, category) == 1216

      assert Enum.all?(
               [:bullet, :blitz, :rapid] -- [category],
               &(ChessDuelBackend.Accounts.User.rating_for(updated, &1) == 1200)
             )
    end)
  end

  defp register_user(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user
  end

  defp finished_game(white_id, black_id, result, initial \\ 180_000, increment \\ 0) do
    Games.create_game(%{
      game_id: Ecto.UUID.generate(),
      status: "finished",
      white_player_id: white_id,
      black_player_id: black_id,
      result: result,
      end_reason: if(result == "draw", do: "draw", else: "checkmate"),
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
      initial_time_ms: initial,
      increment_ms: increment
    })
  end
end
