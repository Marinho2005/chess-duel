defmodule ChessDuelBackend.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    field :game_id, :string
    field :status, :string, default: "waiting"
    field :board_state, :map, default: %{"moves" => []}
    field :current_turn, :string, default: "white"
    field :white_player_id, :string
    field :black_player_id, :string
    field :moves, {:array, :map}, default: []
    field :final_fen, :string
    field :result, :string
    field :end_reason, :string
    field :white_time_remaining_ms, :integer
    field :black_time_remaining_ms, :integer
    field :initial_time_ms, :integer, default: 180_000
    field :increment_ms, :integer, default: 0
    field :finished_at, :utc_datetime
    field :rated_at, :utc_datetime
    field :white_rating_before, :integer
    field :white_rating_after, :integer
    field :black_rating_before, :integer
    field :black_rating_after, :integer
    field :bot_id, :string
    field :bot_color, :string
    field :preparation_ends_at, :utc_datetime_usec

    has_many :rating_changes, ChessDuelBackend.Ratings.RatingChange
    has_one :analysis, ChessDuelBackend.GameAnalysis.Analysis

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :game_id,
      :status,
      :board_state,
      :current_turn,
      :white_player_id,
      :black_player_id,
      :moves,
      :final_fen,
      :result,
      :end_reason,
      :white_time_remaining_ms,
      :black_time_remaining_ms,
      :initial_time_ms,
      :increment_ms,
      :finished_at,
      :bot_id,
      :bot_color,
      :preparation_ends_at
    ])
    |> validate_required([:game_id, :status, :board_state, :current_turn])
    |> validate_inclusion(:status, ~w(waiting in_progress finished))
    |> validate_inclusion(:current_turn, ~w(white black))
    |> validate_inclusion(:result, ~w(white_wins black_wins draw abandoned))
    |> validate_inclusion(
      :end_reason,
      ~w(checkmate timeout stalemate draw abandonment resignation aborted)
    )
    |> validate_inclusion(:bot_color, ~w(white black))
    |> validate_number(:initial_time_ms, greater_than: 0)
    |> validate_number(:increment_ms, greater_than_or_equal_to: 0)
    |> unique_constraint(:game_id)
  end

  def rating_changeset(game, attrs) do
    game
    |> cast(attrs, [
      :rated_at,
      :white_rating_before,
      :white_rating_after,
      :black_rating_before,
      :black_rating_after
    ])
    |> validate_required([
      :rated_at,
      :white_rating_before,
      :white_rating_after,
      :black_rating_before,
      :black_rating_after
    ])
  end
end
