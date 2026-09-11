defmodule ChessDuelBackend.Admin do
  @moduledoc "Consultas administrativas e moderação transacional, sem alterar partidas."
  import Ecto.Query
  alias ChessDuelBackend.Repo
  alias ChessDuelBackend.Accounts.{User, AccountAccess, ModerationAction}
  alias ChessDuelBackend.Games.{Game, GameServer}
  alias ChessDuelBackend.GameAnalysis.Analysis

  @game_fields ~w(id game_id status white_player_id black_player_id result end_reason initial_time_ms increment_ms inserted_at finished_at white_rating_before white_rating_after black_rating_before black_rating_after bot_id bot_color)a

  def dashboard do
    today = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    tomorrow = DateTime.add(today, 86_400)
    games = from g in Game, where: g.inserted_at >= ^today and g.inserted_at < ^tomorrow

    Map.merge(analysis_jobs(), %{
      total_users: Repo.aggregate(User, :count),
      active_games: Enum.count(GameServer.list_active_states(), &(&1.status == "in_progress")),
      games_today: Repo.aggregate(games, :count),
      bot_games_today: Repo.aggregate(from(g in games, where: not is_nil(g.bot_id)), :count),
      day_timezone: "UTC"
    })
  end

  def system do
    %{
      database: if(Repo.query("SELECT 1") |> elem(0) == :ok, do: "available", else: "unavailable"),
      analysis_jobs: analysis_jobs(),
      analysis_queue_concurrency: configured_analysis_concurrency(),
      observed_at: DateTime.utc_now()
    }
  end

  defp configured_analysis_concurrency do
    queues = Application.fetch_env!(:chess_duel_backend, Oban)[:queues]
    if is_list(queues), do: Keyword.get(queues, :analysis), else: nil
  end

  defp analysis_jobs do
    # Estados de jobs, não de game_analyses: uma análise falha pode estar aguardando retry.
    counts =
      from(j in Oban.Job,
        where: j.worker == "ChessDuelBackend.GameAnalysis.Job",
        group_by: j.state,
        select: {j.state, count(j.id)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      pending_analysis_jobs:
        Enum.sum(for state <- ~w(available scheduled retryable), do: Map.get(counts, state, 0)),
      failed_analysis_jobs: Map.get(counts, "discarded", 0),
      executing_analysis_jobs: Map.get(counts, "executing", 0)
    }
  end

  def list_users(params) do
    with :ok <- valid_filter(params["status"], ~w(active suspended banned)) do
      now = DateTime.utc_now()

      query =
        case params["status"] do
          "active" ->
            from u in User,
              where:
                u.account_status == :active or
                  (u.account_status == :suspended and u.suspended_until <= ^now)

          "suspended" ->
            from u in User, where: u.account_status == :suspended and u.suspended_until > ^now

          "banned" ->
            from u in User, where: u.account_status == :banned

          _ ->
            User
        end

      term = search_term(params)

      query =
        if term,
          do: from(u in query, where: ilike(u.nickname, ^term) or ilike(u.email, ^term)),
          else: query

      {:ok, paginate(query, params)}
    end
  end

  def user(id) do
    with {:ok, id} <- uuid(id), %User{} = user <- Repo.get(User, id) do
      actions =
        from(a in ModerationAction,
          where: a.target_user_id == ^id,
          order_by: [desc: a.inserted_at, desc: a.id],
          limit: 50,
          preload: [:admin_user]
        )
        |> Repo.all()

      {:ok, %{user: user, game_summary: game_summary(id), moderation_actions: actions}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp game_summary(id) do
    from(g in Game,
      where: g.white_player_id == ^id or g.black_player_id == ^id,
      select: %{
        total_games: count(g.id),
        finished_games: filter(count(g.id), g.status == "finished"),
        bot_games: filter(count(g.id), not is_nil(g.bot_id)),
        wins:
          filter(
            count(g.id),
            (g.white_player_id == ^id and g.result == "white_wins") or
              (g.black_player_id == ^id and g.result == "black_wins")
          )
      }
    )
    |> Repo.one()
  end

  def moderate(admin_id, target_id, action, params) when action in [:suspend, :ban, :reactivate] do
    with {:ok, target_id} <- uuid(target_id), {:ok, admin_id} <- uuid(admin_id) do
      result =
        Repo.transaction(fn ->
          # Ordem estável evita deadlocks entre dois administradores moderando um ao outro.
          users =
            from(u in User,
              where: u.id in ^[admin_id, target_id],
              order_by: u.id,
              lock: "FOR UPDATE"
            )
            |> Repo.all()
            |> Map.new(&{&1.id, &1})

          admin = users[admin_id]
          target = users[target_id]
          if not AccountAccess.admin?(admin), do: Repo.rollback(:forbidden)
          if is_nil(target), do: Repo.rollback(:not_found)
          if admin_id == target_id, do: Repo.rollback(:self_moderation)
          if not allowed_transition?(target, action), do: Repo.rollback(:invalid_transition)

          audit =
            ModerationAction.changeset(%ModerationAction{}, %{
              target_user_id: target_id,
              admin_user_id: admin_id,
              action: action,
              reason: params["reason"],
              suspended_until: if(action == :suspend, do: params["suspended_until"])
            })
            |> validate_suspension(action)

          if not audit.valid?, do: Repo.rollback(audit)
          until = Ecto.Changeset.get_field(audit, :suspended_until)
          status = %{suspend: :suspended, ban: :banned, reactivate: :active}[action]

          with {:ok, updated} <-
                 target
                 |> Ecto.Changeset.change(account_status: status, suspended_until: until)
                 |> Repo.update(),
               {:ok, _} <- Repo.insert(audit) do
            updated
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, user} ->
          if action in [:suspend, :ban] do
            ChessDuelBackendWeb.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
          end

          {:ok, user}

        error ->
          error
      end
    else
      _ -> {:error, :not_found}
    end
  end

  defp allowed_transition?(user, :suspend), do: AccountAccess.status(user) == :active
  defp allowed_transition?(user, :ban), do: AccountAccess.status(user) != :banned
  defp allowed_transition?(user, :reactivate), do: user.account_status in [:suspended, :banned]

  defp validate_suspension(changeset, :suspend) do
    changeset
    |> Ecto.Changeset.validate_required([:suspended_until])
    |> Ecto.Changeset.validate_change(:suspended_until, fn field, value ->
      if DateTime.compare(value, DateTime.utc_now()) == :gt,
        do: [],
        else: [{field, "deve ser uma data futura"}]
    end)
  end

  defp validate_suspension(changeset, _), do: changeset

  def list_games(params) do
    with :ok <- valid_filter(params["status"], ~w(waiting in_progress finished)),
         :ok <- valid_filter(params["type"], ~w(human bot)),
         :ok <- valid_filter(params["result"], ~w(white_wins black_wins draw abandoned)),
         {:ok, from_date} <- date_filter(params["from"]),
         {:ok, to_date} <- date_filter(params["to"]) do
      query = game_query()

      query =
        if present?(params["status"]),
          do: from([g] in query, where: g.status == ^params["status"]),
          else: query

      query =
        if present?(params["result"]),
          do: from([g] in query, where: g.result == ^params["result"]),
          else: query

      query =
        case params["type"] do
          "human" -> from [g] in query, where: is_nil(g.bot_id)
          "bot" -> from [g] in query, where: not is_nil(g.bot_id)
          _ -> query
        end

      query = if from_date, do: from([g] in query, where: g.inserted_at >= ^from_date), else: query

      query =
        if to_date,
          do: from([g] in query, where: g.inserted_at < ^DateTime.add(to_date, 86_400)),
          else: query

      term = search_term(params)

      query =
        if term,
          do:
            from([g, w, b] in query,
              where: ilike(g.game_id, ^term) or ilike(w.nickname, ^term) or ilike(b.nickname, ^term)
            ),
          else: query

      {:ok, paginate(query, params)}
    end
  end

  def game(id) do
    with {:ok, id} <- uuid(id),
         %{} = result <- from([g] in game_query(), where: g.id == ^id) |> Repo.one() do
      detail =
        from(g in Game,
          where: g.id == ^id,
          select: map(g, [:moves, :final_fen, :white_time_remaining_ms, :black_time_remaining_ms])
        )
        |> Repo.one()

      {:ok, Map.update!(result, :game, &Map.merge(&1, detail))}
    else
      _ -> {:error, :not_found}
    end
  end

  defp game_query do
    from g in Game,
      left_join: w in User,
      on: fragment("?::text", w.id) == g.white_player_id,
      left_join: b in User,
      on: fragment("?::text", b.id) == g.black_player_id,
      left_join: a in Analysis,
      on: a.game_id == g.id,
      select: %{
        game: map(g, ^@game_fields),
        white: map(w, [:id, :nickname, :bullet_rating, :blitz_rating, :rapid_rating]),
        black: map(b, [:id, :nickname, :bullet_rating, :blitz_rating, :rapid_rating]),
        analysis: map(a, [:id, :status, :inserted_at, :updated_at])
      }
  end

  defp paginate(query, params) do
    page = positive_int(params["page"], 1, 100_000)
    per_page = positive_int(params["per_page"], 20, 50)
    total = Repo.aggregate(query, :count)

    entries =
      from(q in query,
        order_by: [desc: q.inserted_at, desc: q.id],
        offset: ^((page - 1) * per_page),
        limit: ^per_page
      )
      |> Repo.all()

    %{
      entries: entries,
      pagination: %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: max(1, ceil(total / per_page)),
        has_more: page * per_page < total
      }
    }
  end

  defp positive_int(value, default, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> min(n, maximum)
      _ -> default
    end
  end

  defp positive_int(_, default, _), do: default

  defp valid_filter(value, allowed),
    do: if(value in [nil, ""] or value in allowed, do: :ok, else: {:error, :invalid_filters})

  defp present?(value), do: is_binary(value) and value != ""

  defp search_term(%{"q" => q}) when is_binary(q) do
    q = q |> String.trim() |> String.slice(0, 160)

    if q != "",
      do:
        "%" <>
          (q
           |> String.replace("\\", "\\\\")
           |> String.replace("%", "\\%")
           |> String.replace("_", "\\_")) <> "%"
  end

  defp search_term(_), do: nil
  defp date_filter(value) when value in [nil, ""], do: {:ok, nil}

  defp date_filter(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
      _ -> {:error, :invalid_filters}
    end
  end

  defp date_filter(_), do: {:error, :invalid_filters}
  defp uuid(value) when is_binary(value), do: Ecto.UUID.cast(value)
  defp uuid(_), do: :error
end
