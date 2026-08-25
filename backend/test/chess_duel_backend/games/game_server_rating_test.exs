defmodule ChessDuelBackend.Games.GameServerRatingTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Games.GameServer

  test "abandono com vencedor persiste resultado, aplica ELO e publica os novos ratings" do
    previous_grace =
      Application.get_env(:chess_duel_backend, :game_abandonment_grace_ms, 60_000)

    Application.put_env(:chess_duel_backend, :game_abandonment_grace_ms, 10)

    on_exit(fn ->
      Application.put_env(
        :chess_duel_backend,
        :game_abandonment_grace_ms,
        previous_grace
      )
    end)

    white = register_user("server-white@example.com", "server_white")
    black = register_user("server-black@example.com", "server_black")
    game_id = Ecto.UUID.generate()

    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "game:#{game_id}")

    assert {:ok, _state} = GameServer.reserve_players(game_id, white.id, black.id)
    assert {:ok, _connection} = GameServer.player_connected(game_id, white.id)
    assert {:ok, _connection} = GameServer.player_connected(game_id, black.id)

    on_exit(fn ->
      case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
        [] -> :ok
      end
    end)

    GameServer.player_disconnected(game_id, white.id)

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "game_over",
                     payload: %{reason: "abandonment", winner_player_id: winner_id}
                   },
                   1_000

    assert winner_id == black.id

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "rating_updated",
                     payload: %{white: white_rating, black: black_rating}
                   },
                   1_000

    assert white_rating == %{id: white.id, before: 1200, after: 1184}
    assert black_rating == %{id: black.id, before: 1200, after: 1216}

    game = Games.get_game_by_game_id(game_id)
    assert game.result == "black_wins"
    assert game.end_reason == "abandonment"
    assert game.rated_at
    assert Accounts.get_user!(white.id).rating == 1184
    assert Accounts.get_user!(black.id).rating == 1216
  end

  defp register_user(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user
  end
end
