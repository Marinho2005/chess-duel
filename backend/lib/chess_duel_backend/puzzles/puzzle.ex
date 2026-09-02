defmodule ChessDuelBackend.Puzzles.Puzzle do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "puzzles" do
    field :lichess_id, :string
    field :fen, :string
    field :moves, {:array, :string}, default: []
    field :rating, :integer
    field :themes, {:array, :string}, default: []
    field :popularity, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(puzzle, attrs) do
    puzzle
    |> cast(attrs, [:lichess_id, :fen, :moves, :rating, :themes, :popularity])
    |> validate_required([:lichess_id, :fen, :moves, :rating, :popularity])
    |> validate_length(:moves, min: 2)
    |> validate_even_move_count()
    |> unique_constraint(:lichess_id)
  end

  defp validate_even_move_count(changeset) do
    validate_change(changeset, :moves, fn :moves, moves ->
      if rem(length(moves), 2) == 0,
        do: [],
        else: [moves: "must contain setup plus complete player/opponent pairs"]
    end)
  end
end
