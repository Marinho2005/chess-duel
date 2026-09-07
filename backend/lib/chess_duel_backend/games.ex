defmodule ChessDuelBackend.Games do
  @moduledoc """
  Contexto responsavel pela persistencia das partidas.
  """

  import Ecto.Query, warn: false

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackend.Games.GameServer
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

  def list_live_human_games(opts \\ []) do
    category_filter = Keyword.get(opts, :category)
    limit = opts |> Keyword.get(:limit, 30) |> max(1) |> min(30)

    states =
      GameServer.list_active_states()
      |> Enum.filter(&live_human?/1)
      |> Enum.filter(&(is_nil(category_filter) or live_category(&1) == category_filter))
      |> Enum.take(limit)

    player_ids = states |> Enum.flat_map(&[&1.white_player_id, &1.black_player_id]) |> Enum.uniq()
    users = from(user in User, where: user.id in ^player_ids) |> Repo.all() |> Map.new(&{&1.id, &1})

    Enum.flat_map(states, fn state ->
      with %User{} = white <- users[state.white_player_id],
           %User{} = black <- users[state.black_player_id] do
        category =
          ChessDuelBackend.Games.TimeControl.rating_category(
            state.initial_time_ms,
            state.increment_ms
          )

        [
          %{
            game_id: state.game_id,
            category: live_category(state),
            white: live_player(white, category, state),
            black: live_player(black, category, state),
            fen: state.fen,
            current_turn: state.current_turn,
            white_time_remaining_ms: state.white_time_remaining_ms,
            black_time_remaining_ms: state.black_time_remaining_ms,
            initial_time_ms: state.initial_time_ms,
            increment_ms: state.increment_ms
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp live_category(%{initial_time_ms: 60_000, increment_ms: 0}), do: "bullet"
  defp live_category(%{initial_time_ms: 180_000, increment_ms: 0}), do: "blitz"
  defp live_category(%{initial_time_ms: 300_000}), do: "blitz_increment"
  defp live_category(%{initial_time_ms: 600_000, increment_ms: 0}), do: "rapid"
  defp live_category(_), do: "blitz"

  defp live_human?(state) do
    state.status == "in_progress" and state.game_type == :registered and
      is_binary(state.white_player_id) and
      is_binary(state.black_player_id) and is_nil(state.bot_id)
  end

  def player_status(user_id) when is_binary(user_id) do
    case ChessDuelBackend.Games.Lobby.presence_status(user_id) do
      status when status in ~w(online away dnd) -> status
      _ -> if connected_to_active_game?(user_id), do: "online", else: "offline"
    end
  catch
    :exit, _ -> if connected_to_active_game?(user_id), do: "online", else: "offline"
  end

  defp connected_to_active_game?(user_id) do
    GameServer.list_active_states()
    |> Enum.any?(fn state ->
      state.status == "in_progress" and Map.get(state.connected_player_counts, user_id, 0) > 0
    end)
  end

  defp live_player(user, category, state),
    do: %{
      id: user.id,
      nickname: user.nickname,
      rating: User.rating_for(user, category),
      country_code: user.country_code,
      avatar_url: user.avatar_path,
      status:
        if(Map.get(state.connected_player_counts, user.id, 0) > 0,
          do: "online",
          else: "offline"
        )
    }

  def list_finished_games_for_user(user_id, opts \\ []) when is_binary(user_id) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    per_page = opts |> Keyword.get(:per_page, 10) |> max(1) |> min(50)
    category = Keyword.get(opts, :category)

    base_query =
      from(game in Game,
        where: game.status == "finished",
        where: game.white_player_id == ^user_id or game.black_player_id == ^user_id,
        where: not is_nil(game.finished_at)
      )
      |> filter_history_category(category)

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

  defp filter_history_category(query, :bullet),
    do: where(query, [game], game.initial_time_ms == 60_000 and game.increment_ms == 0)

  defp filter_history_category(query, :rapid),
    do: where(query, [game], game.initial_time_ms == 600_000 and game.increment_ms == 0)

  defp filter_history_category(query, :blitz),
    do:
      where(
        query,
        [game],
        game.increment_ms == 0 and game.initial_time_ms in [180_000, 300_000]
      )

  defp filter_history_category(query, _category), do: query

  def public_stats_for_user(user_id) when is_binary(user_id) do
    games =
      from(g in Game,
        where:
          g.status == "finished" and
            (g.white_player_id == ^user_id or g.black_player_id == ^user_id),
        order_by: [asc: g.finished_at]
      )
      |> Repo.all()

    results =
      Enum.map(games, fn game -> result_for_player(game.result, player_color(game, user_id)) end)

    wins = Enum.count(results, &(&1 == "win"))

    %{
      total_games: length(results),
      win_rate: if(results == [], do: 0, else: Float.round(wins * 100 / length(results), 1)),
      current_streak: current_streak(results)
    }
  end

  def detailed_stats_for_user(user_id) when is_binary(user_id) do
    games =
      from(g in Game,
        where:
          g.status == "finished" and
            (g.white_player_id == ^user_id or g.black_player_id == ^user_id),
        order_by: [asc: g.finished_at]
      )
      |> Repo.all()

    entries = history_entries(games, user_id)
    results = Enum.map(entries, & &1.result)

    %{
      total_games: length(entries),
      win_rate: win_rate(results),
      current_streak: current_streak(results),
      best_win_streak: best_win_streak(results),
      by_category: grouped_rates(entries, &(&1.rating_category || category_for(&1.time_control))),
      by_color: grouped_rates(entries, & &1.color),
      by_end_reason: Enum.frequencies_by(entries, &normalize_end_reason/1)
    }
  end

  def rating_history_for_user(user_id, opts \\ []) when is_binary(user_id) do
    category = Keyword.get(opts, :category)
    limit = Keyword.get(opts, :limit)

    query =
      from(change in RatingChange,
        where: change.user_id == ^user_id,
        select: %{
          category: change.category,
          rating_before: change.rating_before,
          rating_after: change.rating_after,
          change: change.change,
          recorded_at: change.inserted_at
        }
      )
      |> maybe_filter_rating_category(category)
      |> order_and_limit_rating_history(limit)

    entries = Repo.all(query)
    if is_integer(limit), do: Enum.reverse(entries), else: entries
  end

  defp maybe_filter_rating_category(query, category)
       when category in [:bullet, :blitz, :rapid],
       do: where(query, [change], change.category == ^category)

  defp maybe_filter_rating_category(query, _category), do: query

  defp order_and_limit_rating_history(query, limit) when is_integer(limit) and limit > 0 do
    query
    |> order_by([change], desc: change.inserted_at, desc: change.id)
    |> limit(^limit)
  end

  defp order_and_limit_rating_history(query, _limit) do
    order_by(query, [change], asc: change.inserted_at, asc: change.id)
  end

  defp current_streak([]), do: 0

  defp current_streak(results) do
    latest = List.last(results)
    count = results |> Enum.reverse() |> Enum.take_while(&(&1 == latest)) |> length()
    if latest == "win", do: count, else: -count
  end

  defp win_rate([]), do: 0

  defp win_rate(results),
    do: Float.round(Enum.count(results, &(&1 == "win")) * 100 / length(results), 1)

  defp best_win_streak(results) do
    {best, current} =
      Enum.reduce(results, {0, 0}, fn
        "win", {best, current} -> {max(best, current + 1), current + 1}
        _, {best, _current} -> {best, 0}
      end)

    max(best, current)
  end

  defp grouped_rates(entries, key_fun) do
    entries
    |> Enum.group_by(key_fun)
    |> Map.new(fn {key, rows} ->
      results = Enum.map(rows, & &1.result)

      {key,
       %{
         total: length(rows),
         wins: Enum.count(results, &(&1 == "win")),
         win_rate: win_rate(results)
       }}
    end)
  end

  defp category_for(%{id: id}) when id in ~w(bullet_1_0), do: :bullet
  defp category_for(%{id: id}) when id in ~w(rapid_10_0), do: :rapid
  defp category_for(_), do: :blitz

  defp normalize_end_reason(%{result: "draw"}), do: "draw"

  defp normalize_end_reason(%{end_reason: reason})
       when reason in ["checkmate", "timeout", "abandonment"],
       do: reason

  defp normalize_end_reason(%{end_reason: reason}) when is_binary(reason), do: reason
  defp normalize_end_reason(_), do: "other"

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
        select: {change.game_id, %{change: change.change, category: change.category}}
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
        rating_change: get_in(rating_changes, [game.id, :change]),
        rating_category: get_in(rating_changes, [game.id, :category]),
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
