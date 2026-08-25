defmodule ChessDuelBackend.Repo.Migrations.AddPersistenceFieldsToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :game_id, :string
      add :white_player_id, :string
      add :black_player_id, :string
      add :moves, {:array, :map}, null: false, default: []
      add :final_fen, :string
      add :result, :string
      add :end_reason, :string
      add :white_time_remaining_ms, :integer
      add :black_time_remaining_ms, :integer
      add :finished_at, :utc_datetime
    end

    create unique_index(:games, [:game_id])

    create constraint(:games, :games_result_must_be_valid,
             check: "result IS NULL OR result IN ('white_wins', 'black_wins', 'draw', 'abandoned')"
           )

    create constraint(:games, :games_end_reason_must_be_valid,
             check:
               "end_reason IS NULL OR end_reason IN ('checkmate', 'timeout', 'stalemate', 'draw', 'abandonment')"
           )
  end
end
