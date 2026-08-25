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

    assert Accounts.get_user!(white.id).rating == 1216
    assert Accounts.get_user!(black.id).rating == 1184

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
    assert Accounts.get_user!(white.id).rating == 1216
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
    assert Accounts.get_user!(white.id).rating == 1200
    assert Accounts.get_user!(black.id).rating == 1200
    refute Games.get_game!(game.id).rated_at
  end

  defp register_user(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user
  end

  defp finished_game(white_id, black_id, result) do
    Games.create_game(%{
      game_id: Ecto.UUID.generate(),
      status: "finished",
      white_player_id: white_id,
      black_player_id: black_id,
      result: result,
      end_reason: if(result == "draw", do: "draw", else: "checkmate"),
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
