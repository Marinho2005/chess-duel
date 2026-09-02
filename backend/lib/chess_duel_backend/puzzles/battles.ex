defmodule ChessDuelBackend.Puzzles.Battles do
  @moduledoc "Persistência e rating idempotente das batalhas de puzzles."

  import Ecto.Query

  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Puzzles
  alias ChessDuelBackend.Puzzles.{Battle, BattleParticipant, BattleRatingChange}
  alias ChessDuelBackend.Ratings.Elo
  alias ChessDuelBackend.Repo

  def create(player_one, player_two, duration_seconds) when duration_seconds in [180, 300] do
    puzzles = Puzzles.select_progression()

    if length(puzzles) < 2 do
      {:error, :no_puzzles}
    else
      now = DateTime.utc_now(:second)
      countdown_ms = Application.get_env(:chess_duel_backend, :puzzle_battle_countdown_ms, 3_000)
      started_at = DateTime.add(now, countdown_ms, :millisecond)

      Repo.transaction(fn ->
        battle =
          %Battle{}
          |> Battle.changeset(%{
            duration_seconds: duration_seconds,
            puzzle_ids: Enum.map(puzzles, & &1.id),
            started_at: started_at,
            ends_at: DateTime.add(started_at, duration_seconds, :second)
          })
          |> Repo.insert!()

        participants = [
          insert_participant!(battle.id, player_one.id, "player_one"),
          insert_participant!(battle.id, player_two.id, "player_two")
        ]

        %{
          battle: battle,
          participants: participants,
          players: [player_one, player_two],
          puzzles: puzzles
        }
      end)
    end
  end

  def finish(battle_id, participant_states) do
    Repo.transaction(fn ->
      battle = from(b in Battle, where: b.id == ^battle_id, lock: "FOR UPDATE") |> Repo.one!()

      if battle.rated_at do
        completed_payload(battle)
      else
        participants =
          from(p in BattleParticipant,
            where: p.battle_id == ^battle_id,
            order_by: p.slot,
            lock: "FOR UPDATE"
          )
          |> Repo.all()

        [player_one_participant, player_two_participant] = participants
        one_state = Map.fetch!(participant_states, player_one_participant.user_id)
        two_state = Map.fetch!(participant_states, player_two_participant.user_id)
        result = result_for(one_state, two_state)

        users =
          from(u in User,
            where: u.id in ^[player_one_participant.user_id, player_two_participant.user_id],
            order_by: u.id,
            lock: "FOR UPDATE"
          )
          |> Repo.all()
          |> Map.new(&{&1.id, &1})

        one_user = Map.fetch!(users, player_one_participant.user_id)
        two_user = Map.fetch!(users, player_two_participant.user_id)
        elo = Elo.calculate(one_user.battle_rating, two_user.battle_rating, elo_result(result))

        update_user_rating!(one_user, elo.white_after)
        update_user_rating!(two_user, elo.black_after)
        update_participant!(player_one_participant, one_state)
        update_participant!(player_two_participant, two_state)
        insert_rating_change!(battle.id, one_user.id, elo.white_before, elo.white_after)
        insert_rating_change!(battle.id, two_user.id, elo.black_before, elo.black_after)

        finished_at = DateTime.utc_now(:second)
        winner_id = winner_id(result, one_user.id, two_user.id)

        battle =
          battle
          |> Battle.changeset(%{
            status: "finished",
            result: result,
            winner_id: winner_id,
            finished_at: finished_at,
            rated_at: finished_at
          })
          |> Repo.update!()

        result_payload(battle, one_user, two_user, one_state, two_state, elo)
      end
    end)
  end

  def mark_started(battle_id) do
    from(b in Battle, where: b.id == ^battle_id and b.status == "preparing")
    |> Repo.update_all(set: [status: "in_progress", updated_at: DateTime.utc_now(:second)])

    :ok
  end

  defp insert_participant!(battle_id, user_id, slot) do
    %BattleParticipant{}
    |> BattleParticipant.changeset(%{battle_id: battle_id, user_id: user_id, slot: slot})
    |> Repo.insert!()
  end

  def result_for(one, two) do
    cond do
      one.score > two.score -> "player_one_wins"
      two.score > one.score -> "player_two_wins"
      one.errors < two.errors -> "player_one_wins"
      two.errors < one.errors -> "player_two_wins"
      true -> "draw"
    end
  end

  defp elo_result("player_one_wins"), do: :white_win
  defp elo_result("player_two_wins"), do: :black_win
  defp elo_result("draw"), do: :draw

  defp winner_id("player_one_wins", one_id, _two_id), do: one_id
  defp winner_id("player_two_wins", _one_id, two_id), do: two_id
  defp winner_id("draw", _one_id, _two_id), do: nil

  defp update_user_rating!(user, rating),
    do: user |> User.battle_rating_changeset(rating) |> Repo.update!()

  defp update_participant!(participant, state) do
    participant
    |> BattleParticipant.changeset(%{
      score: state.score,
      errors: state.errors,
      puzzles_attempted: state.puzzles_attempted,
      current_puzzle_index: state.puzzle_index
    })
    |> Repo.update!()
  end

  defp insert_rating_change!(battle_id, user_id, before, after_rating) do
    %BattleRatingChange{}
    |> BattleRatingChange.changeset(%{
      battle_id: battle_id,
      user_id: user_id,
      rating_before: before,
      rating_after: after_rating,
      change: after_rating - before
    })
    |> Repo.insert!()
  end

  defp result_payload(battle, one, two, one_state, two_state, elo) do
    %{
      battle_id: battle.id,
      result: battle.result,
      winner_id: battle.winner_id,
      finished_at: battle.finished_at,
      players: %{
        one.id => player_result(one, one_state, elo.white_before, elo.white_after),
        two.id => player_result(two, two_state, elo.black_before, elo.black_after)
      }
    }
  end

  defp player_result(user, state, before, after_rating) do
    %{
      id: user.id,
      nickname: user.nickname,
      score: state.score,
      errors: state.errors,
      puzzles_attempted: state.puzzles_attempted,
      rating_before: before,
      rating_after: after_rating,
      rating_change: after_rating - before
    }
  end

  defp completed_payload(battle) do
    changes = Repo.all(from(c in BattleRatingChange, where: c.battle_id == ^battle.id))
    participants = Repo.all(from(p in BattleParticipant, where: p.battle_id == ^battle.id))

    %{
      battle_id: battle.id,
      result: battle.result,
      winner_id: battle.winner_id,
      finished_at: battle.finished_at,
      players:
        Map.new(participants, fn participant ->
          change = Enum.find(changes, &(&1.user_id == participant.user_id))

          {participant.user_id,
           %{
             id: participant.user_id,
             score: participant.score,
             errors: participant.errors,
             puzzles_attempted: participant.puzzles_attempted,
             rating_before: change.rating_before,
             rating_after: change.rating_after,
             rating_change: change.change
           }}
        end)
    }
  end
end
