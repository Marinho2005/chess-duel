defmodule ChessDuelBackend.Puzzles do
  @moduledoc "Banco de puzzles Lichess, progresso das tentativas e rating independente."

  import Ecto.Query

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Puzzles.{Attempt, Puzzle, RushScore}
  alias ChessDuelBackend.Repo

  @rating_margins [150, 300, 600]
  @rating_k 32

  def get_puzzle(id), do: Repo.get(Puzzle, id)

  def next_puzzle(user_id, puzzle_rating) do
    completed_ids =
      from(a in Attempt,
        where: a.user_id == ^user_id and not is_nil(a.outcome),
        select: a.puzzle_id
      )
      |> Repo.all()

    with %Puzzle{} = puzzle <- select_puzzle(puzzle_rating, completed_ids),
         {:ok, attempt} <- ensure_attempt(user_id, puzzle.id) do
      {:ok, puzzle, attempt.current_index}
    else
      nil -> {:error, :no_puzzles}
      error -> error
    end
  end

  def select_puzzle(puzzle_rating, excluded_ids \\ []) do
    Enum.find_value(@rating_margins, fn margin ->
      random_in_range(puzzle_rating - margin, puzzle_rating + margin, excluded_ids)
    end) || random_in_range(nil, nil, excluded_ids) || random_in_range(nil, nil, [])
  end

  def select_progression(count \\ 60) do
    from(p in Puzzle,
      where: p.rating >= 650 and p.rating <= 2500,
      where: fragment("cardinality(?) >= 2", p.moves),
      order_by: fragment("RANDOM()"),
      limit: ^count
    )
    |> Repo.all()
    |> Enum.sort_by(& &1.rating)
  end

  def submit_attempt(user_id, puzzle_id, index, move)
      when is_integer(index) and is_binary(move) do
    Repo.transaction(fn ->
      puzzle = Repo.get!(Puzzle, puzzle_id)
      attempt = locked_attempt!(user_id, puzzle_id)

      cond do
        attempt.outcome ->
          Repo.rollback(:already_completed)

        index != attempt.current_index ->
          Repo.rollback({:unexpected_index, attempt.current_index})

        Enum.at(puzzle.moves, index) != move ->
          incorrect_attempt(attempt, puzzle)

        index == length(puzzle.moves) - 1 ->
          resolve_attempt(attempt, puzzle)

        true ->
          automatic_index = index + 1
          next_index = index + 2

          if next_index >= length(puzzle.moves) do
            resolve_attempt(attempt, puzzle)
          else
            attempt
            |> Attempt.changeset(%{current_index: next_index})
            |> Repo.update!()

            %{
              status: :correct,
              resolved: false,
              automatic_move: Enum.at(puzzle.moves, automatic_index),
              next_index: next_index
            }
          end
      end
    end)
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def create_rush_score(attrs) do
    %RushScore{}
    |> RushScore.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :session_id)
  end

  def mode_summary(user_id) do
    user = Repo.get!(User, user_id)

    records =
      from(score in RushScore,
        where: score.user_id == ^user_id,
        group_by: score.duration_seconds,
        select: {score.duration_seconds, max(score.score)}
      )
      |> Repo.all()
      |> Map.new()

    %{
      puzzle_rating: user.puzzle_rating,
      battle_rating: user.battle_rating,
      rush_records: %{180 => Map.get(records, 180, 0), 300 => Map.get(records, 300, 0)}
    }
  end

  def public_puzzle(%Puzzle{} = puzzle, expected_index \\ 1) do
    %{
      id: puzzle.id,
      fen: puzzle.fen,
      rating: puzzle.rating,
      themes: puzzle.themes,
      setup_move: List.first(puzzle.moves),
      played_moves: Enum.take(puzzle.moves, expected_index),
      expected_index: expected_index,
      instructions: "Apply played_moves in order, then wait for the player's move."
    }
  end

  def uci_move(from, to, promotion) do
    normalized_promotion =
      case promotion do
        value when value in ["q", "r", "b", "n"] -> value
        nil -> ""
        "" -> ""
        _ -> :invalid
      end

    if valid_square?(from) and valid_square?(to) and normalized_promotion != :invalid do
      {:ok, from <> to <> normalized_promotion}
    else
      {:error, :invalid_move}
    end
  end

  defp random_in_range(minimum, maximum, excluded_ids) do
    query = from(p in Puzzle, where: fragment("cardinality(?) >= 2", p.moves))

    query =
      if minimum && maximum,
        do: where(query, [p], p.rating >= ^minimum and p.rating <= ^maximum),
        else: query

    query =
      if excluded_ids == [], do: query, else: where(query, [p], p.id not in ^excluded_ids)

    query |> order_by(fragment("RANDOM()")) |> limit(1) |> Repo.one()
  end

  defp ensure_attempt(user_id, puzzle_id) do
    attrs = %{user_id: user_id, puzzle_id: puzzle_id, current_index: 1}

    %Attempt{}
    |> Attempt.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :puzzle_id])

    case Repo.get_by(Attempt, user_id: user_id, puzzle_id: puzzle_id) do
      %Attempt{resolved_at: nil} = attempt -> {:ok, attempt}
      %Attempt{} -> {:error, :already_resolved}
      nil -> {:error, :attempt_not_created}
    end
  end

  defp locked_attempt!(user_id, puzzle_id) do
    from(a in Attempt,
      where: a.user_id == ^user_id and a.puzzle_id == ^puzzle_id,
      lock: "FOR UPDATE"
    )
    |> Repo.one!()
  end

  defp incorrect_attempt(attempt, puzzle) do
    complete_classic_attempt(attempt, puzzle, "incorrect", 0.0)
  end

  defp resolve_attempt(attempt, puzzle) do
    complete_classic_attempt(attempt, puzzle, "correct", 1.0)
  end

  defp complete_classic_attempt(attempt, puzzle, outcome, score) do
    now = DateTime.utc_now(:second)
    rating = update_puzzle_rating!(attempt.user_id, puzzle.rating, score)
    time_spent_ms = max(DateTime.diff(now, attempt.inserted_at, :millisecond), 0)

    attrs = %{
      outcome: outcome,
      completed_at: now,
      failed_at: if(outcome == "incorrect", do: now),
      resolved_at: if(outcome == "correct", do: now),
      rating_before: rating.before,
      rating_after: rating.after,
      rating_change: rating.change,
      time_spent_ms: time_spent_ms
    }

    attempt |> Attempt.changeset(attrs) |> Repo.update!()

    %{
      status: if(outcome == "correct", do: :correct, else: :incorrect),
      resolved: outcome == "correct",
      completed: true,
      automatic_move: nil,
      puzzle_rating: rating.after,
      rating_before: rating.before,
      rating_after: rating.after,
      rating_change: rating.change,
      time_spent_ms: time_spent_ms
    }
  end

  # Elo simples: K=32 e o rating do puzzle ocupa o papel do oponente. Acerto vale
  # 1 e o primeiro erro no puzzle vale 0. Reenvios não alteram rating novamente.
  defp update_puzzle_rating!(user_id, puzzle_rating, score) do
    user =
      from(u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
      |> Repo.one!()

    expected = 1.0 / (1.0 + :math.pow(10.0, (puzzle_rating - user.puzzle_rating) / 400.0))
    before = user.puzzle_rating
    new_rating = max(100, before + round(@rating_k * (score - expected)))
    user |> User.puzzle_rating_changeset(new_rating) |> Repo.update!()
    %{before: before, after: new_rating, change: new_rating - before}
  end

  defp valid_square?(<<file, rank>>), do: file in ?a..?h and rank in ?1..?8
  defp valid_square?(_), do: false
end
