defmodule ChessDuelBackend.Games.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "games" do
    field :status, :string, default: "waiting"
    field :board_state, :map, default: %{"moves" => []}
    field :current_turn, :string, default: "white"

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:status, :board_state, :current_turn])
    |> validate_required([:status, :board_state, :current_turn])
    |> validate_inclusion(:status, ~w(waiting in_progress finished))
    |> validate_inclusion(:current_turn, ~w(white black))
  end
end
