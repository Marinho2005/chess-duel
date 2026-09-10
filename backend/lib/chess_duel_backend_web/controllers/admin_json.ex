defmodule ChessDuelBackendWeb.AdminJSON do
  alias ChessDuelBackend.Accounts.{User, AccountAccess}
  alias ChessDuelBackend.Games.{Bots, TimeControl}

  def user(user) do
    %{
      id: user.id,
      nickname: user.nickname,
      email: user.email,
      rating: user.blitz_rating,
      ratings: User.ratings(user),
      puzzle_rating: user.puzzle_rating,
      battle_rating: user.battle_rating,
      role: user.role,
      account_status: AccountAccess.status(user),
      suspended_until: user.suspended_until,
      inserted_at: user.inserted_at,
      country: user.country,
      country_code: user.country_code,
      avatar_url: user.avatar_path,
      confirmed_at: user.confirmed_at
    }
  end

  def moderation(action) do
    %{
      id: action.id,
      action: action.action,
      reason: action.reason,
      admin: %{id: action.admin_user.id, nickname: action.admin_user.nickname},
      suspended_until: action.suspended_until,
      inserted_at: action.inserted_at
    }
  end

  def game(%{game: game, white: white, black: black, analysis: analysis}) do
    category = TimeControl.rating_category(game.initial_time_ms, game.increment_ms)

    data = %{
      id: game.id,
      game_id: game.game_id,
      status: game.status,
      white: player(white, game, :white, category),
      black: player(black, game, :black, category),
      type: if(game.bot_id, do: "bot", else: "human"),
      result: game.result,
      end_reason: game.end_reason,
      time_control: TimeControl.from_values(game.initial_time_ms, game.increment_ms),
      inserted_at: game.inserted_at,
      finished_at: game.finished_at,
      analysis: analysis
    }

    Map.merge(
      data,
      Map.take(game, [:moves, :final_fen, :white_time_remaining_ms, :black_time_remaining_ms])
    )
  end

  defp player(user, game, color, category) do
    before_rating =
      Map.get(game, if(color == :white, do: :white_rating_before, else: :black_rating_before))

    after_rating =
      Map.get(game, if(color == :white, do: :white_rating_after, else: :black_rating_after))

    bot = if game.bot_color == Atom.to_string(color), do: Bots.get(game.bot_id)

    cond do
      bot ->
        %{
          id: nil,
          nickname: bot.name,
          bot: true,
          rating: bot.rating,
          rating_before: before_rating,
          rating_after: after_rating
        }

      user ->
        %{
          id: user.id,
          nickname: user.nickname,
          bot: false,
          rating: Map.fetch!(user, User.rating_field(category)),
          rating_before: before_rating,
          rating_after: after_rating
        }

      true ->
        %{
          id: nil,
          nickname: "Aguardando jogador",
          bot: false,
          rating: nil,
          rating_before: before_rating,
          rating_after: after_rating
        }
    end
  end
end
