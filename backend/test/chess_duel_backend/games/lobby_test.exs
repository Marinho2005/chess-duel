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
             Lobby.create_challenge(white.id, black.id, "blitz_5_0")

    assert challenge.challenger.nickname == "lobby_white"
    assert challenge.time_control.label == "Blitz 5+0"

    assert {:ok, game, %{challenges: []}} = Lobby.accept_challenge(challenge.id, black.id)
    assert game.white_player.id == white.id
    assert game.black_player.id == black.id
    assert game.time_control.id == "blitz_5_0"

    assert {:ok, state} = GameServer.get_state(game.game_id)
    assert state.white_player_id == white.id
    assert state.black_player_id == black.id
    assert state.initial_time_ms == 300_000
    assert state.increment_ms == 0
    assert state.white_time_remaining_ms <= 300_000
    assert state.white_time_remaining_ms > 299_500
    assert state.black_time_remaining_ms == 300_000

    Process.sleep(150)
    persisted_game = Games.get_game_by_game_id(game.game_id)
    assert persisted_game.initial_time_ms == 300_000
    assert persisted_game.increment_ms == 0

    {:ok, game_pid} = GameServer.start_or_get(game.game_id)
    DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, game_pid)
    Lobby.disconnect(white.id)
    Lobby.disconnect(black.id)
  end

  test "presenca controla visibilidade e recebimento de desafios" do
    online = register_user("presence-online@example.com", "presence_online")
    other = register_user("presence-other@example.com", "presence_other")

    Lobby.connect(online)
    Lobby.connect(other)

    assert {:ok, %{users: users}} = Lobby.set_presence(other.id, "away")
    assert Enum.find(users, &(&1.id == other.id)).status == "away"
    assert Lobby.presence_status(other.id) == "away"

    assert {:ok, %{users: users}} = Lobby.set_presence(other.id, "dnd")
    assert Enum.find(users, &(&1.id == other.id)).status == "dnd"
    assert {:error, :user_unavailable} = Lobby.create_challenge(online.id, other.id)

    assert {:ok, %{users: users}} = Lobby.set_presence(other.id, "invisible")
    refute Enum.any?(users, &(&1.id == other.id))
    assert Lobby.presence_status(other.id) == "offline"

    assert {:error, :invalid_presence} = Lobby.set_presence(other.id, "busy-ish")

    Lobby.disconnect(online.id)
    Lobby.disconnect(other.id)
  end

  test "desafio direto permanece pendente quando o amigo esta offline" do
    challenger = register_user("friend-challenger@example.com", "friend_challenger")
    challenged = register_user("friend-challenged@example.com", "friend_challenged")

    Lobby.connect(challenger)

    assert {:ok, %{challenges: [challenge]}} =
             Lobby.create_direct_challenge(challenger, challenged, "rapid_10_0")

    assert challenge.challenged.id == challenged.id
    assert challenge.challenged.status == "offline"
    assert challenge.time_control.id == "rapid_10_0"
    assert is_binary(challenge.expires_at)

    assert %{challenges: [persisted]} = Lobby.disconnect(challenger.id)
    assert persisted.id == challenge.id

    assert %{challenges: [received]} = Lobby.connect(challenged)
    assert received.id == challenge.id

    assert {:ok, game, %{challenges: []}} =
             Lobby.accept_challenge(challenge.id, challenged.id)

    assert game.white_player.id == challenger.id
    assert game.black_player.id == challenged.id

    Process.sleep(150)
    {:ok, game_pid} = GameServer.start_or_get(game.game_id)
    DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, game_pid)
    Lobby.disconnect(challenged.id)
  end

  test "desafio direto expira e respeita nao perturbar" do
    challenger = register_user("friend-expire-a@example.com", "friend_expire_a")
    challenged = register_user("friend-expire-b@example.com", "friend_expire_b")

    Lobby.connect(challenger)
    Lobby.connect(challenged)
    assert {:ok, _state} = Lobby.set_presence(challenged.id, "dnd")

    assert {:error, :user_unavailable} =
             Lobby.create_direct_challenge(challenger, challenged)

    assert {:ok, _state} = Lobby.set_presence(challenged.id, "online")

    assert {:ok, %{challenges: [challenge]}} =
             Lobby.create_direct_challenge(challenger, challenged)

    send(Process.whereis(Lobby), {:expire_challenge, challenge.id})
    assert %{challenges: []} = Lobby.connect(challenger)

    Lobby.disconnect(challenger.id)
    Lobby.disconnect(challenger.id)
    Lobby.disconnect(challenged.id)
  end

  test "somente o desafiante pode cancelar um desafio pendente" do
    challenger = register_user("cancel-challenge-a@example.com", "cancel_challenge_a")
    challenged = register_user("cancel-challenge-b@example.com", "cancel_challenge_b")

    Lobby.connect(challenger)

    assert {:ok, %{challenges: [challenge]}} =
             Lobby.create_direct_challenge(challenger, challenged)

    assert {:error, :not_challenger} = Lobby.cancel_challenge(challenge.id, challenged.id)
    assert {:ok, %{challenges: []}} = Lobby.cancel_challenge(challenge.id, challenger.id)

    Lobby.disconnect(challenger.id)
  end

  test "um jogador pode manter e cancelar desafios para adversarios diferentes" do
    challenger = register_user("multiple-challenge-a@example.com", "multiple_challenge_a")
    first_opponent = register_user("multiple-challenge-b@example.com", "multiple_challenge_b")
    second_opponent = register_user("multiple-challenge-c@example.com", "multiple_challenge_c")

    Lobby.connect(challenger)

    assert {:ok, %{challenges: [first_challenge]}} =
             Lobby.create_direct_challenge(challenger, first_opponent, "bullet_1_0")

    assert {:ok, %{challenges: challenges}} =
             Lobby.create_direct_challenge(challenger, second_opponent, "rapid_10_0")

    assert length(challenges) == 2

    assert Enum.sort(Enum.map(challenges, & &1.challenged.id)) ==
             Enum.sort([first_opponent.id, second_opponent.id])

    assert {:ok, %{challenges: []}} = Lobby.cancel_challenges(challenger.id)

    assert first_challenge.id in Enum.map(challenges, & &1.id)
    Lobby.disconnect(challenger.id)
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
