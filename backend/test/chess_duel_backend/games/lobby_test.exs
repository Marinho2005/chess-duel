defmodule ChessDuelBackend.Games.LobbyTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Games.{GameServer, Lobby}

  test "desafio aceito cria uma partida exclusiva com jogadores reservados" do
    white = register_user("lobby-white@example.com", "lobby_white")
    black = register_user("lobby-black@example.com", "lobby_black")

    Lobby.connect(white)
    Lobby.connect(black)

    assert {:error, :invalid_time_control} =
             Lobby.create_challenge(white.id, black.id, "formato_inexistente")

    assert {:ok, %{challenges: [challenge]}} =
             Lobby.create_challenge(white.id, black.id, "blitz_5_3")

    assert challenge.challenger.nickname == "lobby_white"
    assert challenge.time_control.label == "Blitz 5+3"

    assert {:ok, game, %{challenges: []}} = Lobby.accept_challenge(challenge.id, black.id)
    assert game.white_player.id == white.id
    assert game.black_player.id == black.id
    assert game.time_control.id == "blitz_5_3"

    assert {:ok, state} = GameServer.get_state(game.game_id)
    assert state.white_player_id == white.id
    assert state.black_player_id == black.id
    assert state.initial_time_ms == 300_000
    assert state.increment_ms == 3_000
    assert state.white_time_remaining_ms == 300_000
    assert state.black_time_remaining_ms == 300_000

    Process.sleep(150)
    persisted_game = Games.get_game_by_game_id(game.game_id)
    assert persisted_game.initial_time_ms == 300_000
    assert persisted_game.increment_ms == 3_000

    {:ok, game_pid} = GameServer.start_or_get(game.game_id)
    DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, game_pid)
    Lobby.disconnect(white.id)
    Lobby.disconnect(black.id)
  end

  defp register_user(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{
        email: email,
        nickname: nickname,
        password: "password1234"
      })

    user
  end
end
