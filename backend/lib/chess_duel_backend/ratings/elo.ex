defmodule ChessDuelBackend.Ratings.Elo do
  @moduledoc "Calculo puro de rating ELO para partidas entre dois jogadores."

  @k_factor 32

  def calculate(white_rating, black_rating, result)
      when is_integer(white_rating) and is_integer(black_rating) and
             result in [:white_win, :black_win, :draw] do
    white_score = score(result)
    white_expected = expected_score(white_rating, black_rating)
    white_change = round(@k_factor * (white_score - white_expected))

    %{
      white_before: white_rating,
      white_after: white_rating + white_change,
      white_change: white_change,
      black_before: black_rating,
      black_after: black_rating - white_change,
      black_change: -white_change
    }
  end

  def expected_score(rating, opponent_rating) do
    1.0 / (1.0 + :math.pow(10.0, (opponent_rating - rating) / 400.0))
  end

  defp score(:white_win), do: 1.0
  defp score(:black_win), do: 0.0
  defp score(:draw), do: 0.5
end
