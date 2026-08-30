defmodule ChessDuelBackend.GameAnalysis.Analysis do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "game_analyses" do
    field :status, :string, default: "pending"
    field :results, :map
    field :error, :string
    belongs_to :game, ChessDuelBackend.Games.Game
    timestamps(type: :utc_datetime)
  end

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [:game_id, :status, :results, :error])
    |> validate_required([:game_id, :status])
    |> validate_inclusion(:status, ~w(pending processing completed failed))
    |> unique_constraint(:game_id)
  end
end
