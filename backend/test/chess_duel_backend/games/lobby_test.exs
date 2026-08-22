defmodule ChessDuelBackend.Games.LobbyTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games.{GameServer, Lobby}

  test "desafio aceito cria uma partida exclusiva com jogadores reservados" do
    white = register_user("lobby-white@example.com", "lobby_white")
    black = register_user("lobby-black@example.com", "lobby_black")

    Lobby.connect(white)
    Lobby.connect(black)

    assert {:ok, %{challenges: [challenge]}} = Lobby.create_challenge(white.id, black.id)
    assert challenge.challenger.nickname == "lobby_white"

    assert {:ok, game, %{challenges: []}} = Lobby.accept_challenge(challenge.id, black.id)
    assert game.white_player.id == white.id
    assert game.black_player.id == black.id

    assert {:ok, state} = GameServer.get_state(game.game_id)
    assert state.white_player_id == white.id
    assert state.black_player_id == black.id

    Process.sleep(150)
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
