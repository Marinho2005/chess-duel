defmodule ChessDuelBackend.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "waiting"
      add :board_state, :map, null: false, default: %{"moves" => []}
      add :current_turn, :string, null: false, default: "white"

      timestamps(type: :utc_datetime)
    end

    create constraint(:games, :games_status_must_be_valid,
             check: "status IN ('waiting', 'in_progress', 'finished')"
           )

    create constraint(:games, :games_current_turn_must_be_valid,
             check: "current_turn IN ('white', 'black')"
           )
  end
end
