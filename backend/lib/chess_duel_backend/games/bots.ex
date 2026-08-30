defmodule ChessDuelBackend.Games.Bots do
  @moduledoc "Catálogo autoritativo dos bots e do mapeamento de força para Stockfish."

  @bots [
    %{
      id: "clark",
      name: "Clark",
      rating: 800,
      difficulty: "Iniciante",
      persona: "explorer",
      stockfish: [skill_level: 0, movetime_ms: 70]
    },
    %{
      id: "jonathan",
      name: "Jonathan",
      rating: 1200,
      difficulty: "Casual",
      persona: "chill",
      stockfish: [skill_level: 3, movetime_ms: 110]
    },
    %{
      id: "renan",
      name: "Renan",
      rating: 1600,
      difficulty: "Intermediário",
      persona: "focused",
      stockfish: [limit_strength: true, elo: 1600, movetime_ms: 180]
    },
    %{
      id: "boris",
      name: "Boris",
      rating: 2400,
      difficulty: "Mestre",
      persona: "master",
      stockfish: [limit_strength: true, elo: 2400, movetime_ms: 350]
    },
    %{
      id: "terminator",
      name: "Terminator",
      rating: 2800,
      difficulty: "Extremo",
      persona: "robot",
      stockfish: [limit_strength: true, elo: 2800, movetime_ms: 600]
    }
  ]

  def all, do: @bots
  def get(id) when is_binary(id), do: Enum.find(@bots, &(&1.id == id))
  def get(_), do: nil

  def public(bot) do
    Map.take(bot, [:id, :name, :rating, :difficulty, :persona])
    |> Map.put(:nickname, bot.name)
    |> Map.put(:bot, true)
    |> Map.put(:avatar_url, nil)
  end

  def player_id(bot_id), do: "bot:#{bot_id}"
end
