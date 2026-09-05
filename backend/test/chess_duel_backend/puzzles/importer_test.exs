defmodule ChessDuelBackend.Puzzles.ImporterTest do
  use ChessDuelBackend.DataCase, async: true

  alias ChessDuelBackend.Puzzles.{Importer, Puzzle}

  test "interpreta CSV, filtra popularidade e preserva a sequência Lichess completa" do
    path = Path.join(System.tmp_dir!(), "puzzles-#{System.unique_integer([:positive])}.csv")

    File.write!(path, """
    PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
    sample1,8/8/8/8/8/8/8/K6k w - - 0 1,a1a2 h1h2 a2a3 h2h3,900,80,95,10,mate short,https://lichess.org/a,
    ignored,8/8/8/8/8/8/8/K6k w - - 0 1,a1a2 h1h2,1200,80,20,10,quietMove,https://lichess.org/b,
    """)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, %{imported: 1, skipped: 1}} =
             Importer.import(path, limit: 5, minimum_popularity: 80)

    assert %Puzzle{lichess_id: "sample1", moves: ["a1a2", "h1h2", "a2a3", "h2h3"]} =
             Repo.get_by(Puzzle, lichess_id: "sample1")
  end

  test "faz parse de campos CSV entre aspas e aspas escapadas" do
    assert ["id", "fen,with,commas", "a\"b"] ==
             Importer.parse_csv_line(~s(id,"fen,with,commas","a""b"))
  end
end
