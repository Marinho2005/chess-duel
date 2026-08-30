defmodule ChessDuelBackend.Repo.Migrations.AllowBotGameEndReasons do
  use Ecto.Migration

  def up do
    drop constraint(:games, :games_end_reason_must_be_valid)

    create constraint(:games, :games_end_reason_must_be_valid,
             check:
               "end_reason IS NULL OR end_reason IN ('checkmate', 'timeout', 'stalemate', 'draw', 'abandonment', 'resignation', 'aborted')"
           )
  end

  def down do
    drop constraint(:games, :games_end_reason_must_be_valid)

    create constraint(:games, :games_end_reason_must_be_valid,
             check:
               "end_reason IS NULL OR end_reason IN ('checkmate', 'timeout', 'stalemate', 'draw', 'abandonment')"
           )
  end
end
