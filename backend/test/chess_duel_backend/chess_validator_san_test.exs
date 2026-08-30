defmodule ChessDuelBackend.ChessValidatorSanTest do
  use ExUnit.Case, async: false

  alias ChessDuelBackend.ChessValidator

  test "retorna SAN para movimento normal e captura" do
    assert {:ok, first} = ChessValidator.validate_move(start_fen(), "e2", "e4")
    assert first.san == "e4"
    assert {:ok, second} = ChessValidator.validate_move(first.new_fen, "d7", "d5")
    assert {:ok, capture} = ChessValidator.validate_move(second.new_fen, "e4", "d5")
    assert capture.san == "exd5"
    assert capture.captured == "p"
  end

  test "retorna SAN para roque, promoção, xeque, mate e desambiguação" do
    assert {:ok, castle} =
             ChessValidator.validate_move("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1", "g1")

    assert castle.san == "O-O"

    assert {:ok, promotion} =
             ChessValidator.validate_move("8/P7/8/8/8/8/7k/4K3 w - - 0 1", "a7", "a8", "q")

    assert promotion.san =~ ~r/^a8=Q/

    assert {:ok, check} =
             ChessValidator.validate_move("7k/8/8/8/8/8/8/K2Q4 w - - 0 1", "d1", "h5")

    assert check.san == "Qh5+"

    assert {:ok, mate} =
             ChessValidator.validate_move("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1", "f7", "g7")

    assert mate.san == "Qg7#"

    assert {:ok, disambiguated} =
             ChessValidator.validate_move("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "b1", "d2")

    assert disambiguated.san == "Nbd2"
  end

  defp start_fen, do: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
end
