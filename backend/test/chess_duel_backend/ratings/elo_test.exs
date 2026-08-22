defmodule ChessDuelBackend.Ratings.EloTest do
  use ExUnit.Case, async: true

  alias ChessDuelBackend.Ratings.Elo

  test "vitoria entre jogadores iguais transfere 16 pontos" do
    assert %{
             white_after: 1216,
             white_change: 16,
             black_after: 1184,
             black_change: -16
           } = Elo.calculate(1200, 1200, :white_win)
  end

  test "azarão ganha mais pontos ao vencer favorito" do
    assert %{white_after: 1229, black_after: 1571} = Elo.calculate(1200, 1600, :white_win)
  end

  test "empate entre jogadores iguais nao altera rating" do
    assert %{white_change: 0, black_change: 0} = Elo.calculate(1200, 1200, :draw)
  end
end
