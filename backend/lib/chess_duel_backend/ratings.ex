defmodule ChessDuelBackend.Ratings do
  @moduledoc "Atualiza ratings de partidas finalizadas de forma atomica e idempotente."

  import Ecto.Query

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackend.Ratings.{Elo, RatingChange}
  alias ChessDuelBackend.Repo

  def rate_game(game_id) when is_binary(game_id) do
    Repo.transact(fn ->
      game = Repo.one(from g in Game, where: g.game_id == ^game_id, lock: "FOR UPDATE")

      case game do
        nil -> Repo.rollback(:game_not_found)
        %Game{rated_at: rated_at} when not is_nil(rated_at) -> {:ok, :already_rated}
        %Game{status: status} when status != "finished" -> Repo.rollback(:game_not_finished)
        %Game{bot_id: bot_id} when not is_nil(bot_id) -> Repo.rollback(:game_not_rateable)
        game -> rate_finished_game(game)
      end
    end)
  end

  defp rate_finished_game(game) do
    with {:ok, result} <- rating_result(game.result),
         {:ok, white_id} <- Ecto.UUID.cast(game.white_player_id),
         {:ok, black_id} <- Ecto.UUID.cast(game.black_player_id),
         true <- white_id != black_id do
      users =
        Repo.all(
          from u in User,
            where: u.id in ^[white_id, black_id],
            order_by: u.id,
            lock: "FOR UPDATE"
        )

      users_by_id = Map.new(users, &{&1.id, &1})

      with %User{} = white <- users_by_id[white_id],
           %User{} = black <- users_by_id[black_id] do
        persist_rating(game, white, black, result)
      else
        _ -> Repo.rollback(:players_not_found)
      end
    else
      {:error, reason} -> Repo.rollback(reason)
      false -> Repo.rollback(:invalid_players)
      :error -> Repo.rollback(:invalid_players)
    end
  end

  defp persist_rating(game, white, black, result) do
    calculation = Elo.calculate(white.rating, black.rating, result)

    white = Repo.update!(User.rating_changeset(white, calculation.white_after))
    black = Repo.update!(User.rating_changeset(black, calculation.black_after))

    insert_change!(game, white, calculation.white_before, calculation.white_after)
    insert_change!(game, black, calculation.black_before, calculation.black_after)

    rated_at = DateTime.utc_now() |> DateTime.truncate(:second)

    game
    |> Game.rating_changeset(%{
      rated_at: rated_at,
      white_rating_before: calculation.white_before,
      white_rating_after: calculation.white_after,
      black_rating_before: calculation.black_before,
      black_rating_after: calculation.black_after
    })
    |> Repo.update!()

    {:ok,
     %{
       game_id: game.game_id,
       white: %{id: white.id, before: calculation.white_before, after: calculation.white_after},
       black: %{id: black.id, before: calculation.black_before, after: calculation.black_after}
     }}
  end

  defp insert_change!(game, user, before, after_rating) do
    %RatingChange{}
    |> RatingChange.changeset(%{
      game_id: game.id,
      user_id: user.id,
      rating_before: before,
      rating_after: after_rating,
      change: after_rating - before
    })
    |> Repo.insert!()
  end

  defp rating_result("white_wins"), do: {:ok, :white_win}
  defp rating_result("black_wins"), do: {:ok, :black_win}
  defp rating_result("draw"), do: {:ok, :draw}
  defp rating_result(_result), do: {:error, :game_not_rateable}
end
