defmodule ChessDuelBackend.Games do
  @moduledoc """
  Contexto responsavel pela persistencia das partidas.
  """

  import Ecto.Query, warn: false

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackend.Games.Bots
  alias ChessDuelBackend.Ratings.RatingChange
  alias ChessDuelBackend.Repo

  def create_game(attrs \\ %{}) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def get_game!(id), do: Repo.get!(Game, id)
  def get_game_by_game_id(game_id), do: Repo.get_by(Game, game_id: game_id)

  def get_or_create_game(game_id, attrs) do
    case get_game_by_game_id(game_id) do
      nil -> create_game(Map.put(attrs, :game_id, game_id))
      game -> {:ok, game}
    end
  end

  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  def list_finished_games_for_user(user_id, opts \\ []) when is_binary(user_id) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    per_page = opts |> Keyword.get(:per_page, 10) |> max(1) |> min(50)

    base_query =
      from game in Game,
        where: game.status == "finished",
        where: game.white_player_id == ^user_id or game.black_player_id == ^user_id,
        where: not is_nil(game.finished_at)

    total = Repo.aggregate(base_query, :count, :id)

    games =
      base_query
      |> order_by([game], desc: game.finished_at, desc: game.id)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> Repo.all()

    entries = history_entries(games, user_id)

    %{
      games: entries,
      pagination: %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: ceil_div(total, per_page),
        has_more: page * per_page < total
      }
    }
  end

  defp history_entries([], _user_id), do: []

  defp history_entries(games, user_id) do
    opponent_ids =
      games
      |> Enum.map(&opponent_id(&1, user_id))
      |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))
      |> Enum.uniq()

    opponents =
      from(user in User, where: user.id in ^opponent_ids, select: {user.id, user.nickname})
      |> Repo.all()
      |> Map.new()

    game_ids = Enum.map(games, & &1.id)

    rating_changes =
      from(change in RatingChange,
        where: change.user_id == ^user_id and change.game_id in ^game_ids,
        select: {change.game_id, change.change}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(games, fn game ->
      color = player_color(game, user_id)
      opponent_id = opponent_id(game, user_id)

      opponent =
        if game.bot_id do
          bot = Bots.get(game.bot_id)
          %{id: Bots.player_id(game.bot_id), nickname: bot.name, bot: true, rating: bot.rating}
        else
          %{
            id: opponent_id,
            nickname: Map.get(opponents, opponent_id, "Jogador desconhecido"),
            bot: false
          }
        end

      %{
        id: game.id,
        opponent: opponent,
        color: color,
        result: result_for_player(game.result, color),
        end_reason: game.end_reason,
        rating_change: Map.get(rating_changes, game.id),
        time_control:
          ChessDuelBackend.Games.TimeControl.from_values(
            game.initial_time_ms,
            game.increment_ms
          ),
        finished_at: game.finished_at
      }
    end)
  end

  defp player_color(%Game{white_player_id: user_id}, user_id), do: "white"
  defp player_color(_game, _user_id), do: "black"

  defp opponent_id(%Game{white_player_id: user_id, black_player_id: opponent_id}, user_id),
    do: opponent_id

  defp opponent_id(%Game{white_player_id: opponent_id}, _user_id), do: opponent_id

  defp result_for_player("draw", _color), do: "draw"
  defp result_for_player("abandoned", _color), do: "draw"
  defp result_for_player("white_wins", "white"), do: "win"
  defp result_for_player("black_wins", "black"), do: "win"
  defp result_for_player(_result, _color), do: "loss"

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)
end
