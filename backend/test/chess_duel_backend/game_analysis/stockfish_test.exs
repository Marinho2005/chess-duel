defmodule ChessDuelBackend.GameAnalysis.StockfishTest do
  use ExUnit.Case, async: true

  alias ChessDuelBackend.GameAnalysis.Stockfish

  test "interpreta avaliações centipawn e mate do protocolo UCI" do
    assert Stockfish.parse_score("info depth 12 score cp -34 nodes 10") == %{
             "type" => "cp",
             "value" => -34
           }

    assert Stockfish.parse_score("info depth 12 score mate 3 pv e7e8q") == %{
             "type" => "mate",
             "value" => 3
           }
  end

  test "classifica a perda de centipawns" do
    assert Stockfish.classify(0, "e2e4", "e2e4") == "best"
    assert Stockfish.classify(40, "e2e4", "d2d4") == "good"
    assert Stockfish.classify(80, "e2e4", "d2d4") == "inaccuracy"
    assert Stockfish.classify(200, "e2e4", "d2d4") == "mistake"
    assert Stockfish.classify(400, "e2e4", "d2d4") == "blunder"
  end
end
