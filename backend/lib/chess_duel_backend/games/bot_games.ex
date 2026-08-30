defmodule ChessDuelBackend.Games.BotGames do
  alias ChessDuelBackend.Games.{Bots, GameServer, TimeControl}

  def create(user_id, bot_id, time_control_id, color_choice) do
    with bot when not is_nil(bot) <- Bots.get(bot_id),
         {:ok, control} <- TimeControl.fetch(time_control_id),
         {:ok, human_color} <- choose_color(color_choice),
         game_id = Ecto.UUID.generate(),
         {:ok, _state} <- GameServer.reserve_bot_game(game_id, user_id, bot, human_color, control) do
      {:ok,
       %{game_id: game_id, bot: Bots.public(bot), human_color: human_color, time_control: control}}
    else
      nil -> {:error, :invalid_bot_or_time_control}
      error -> error
    end
  end

  defp choose_color("white"), do: {:ok, "white"}
  defp choose_color("black"), do: {:ok, "black"}
  defp choose_color("random"), do: {:ok, Enum.random(["white", "black"])}
  defp choose_color(_), do: {:error, :invalid_color}
end
