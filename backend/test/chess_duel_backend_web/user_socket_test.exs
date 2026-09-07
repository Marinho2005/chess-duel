defmodule ChessDuelBackendWeb.UserSocketTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  require Phoenix.ChannelTest

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.Guest
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.{Repo, Social}
  alias ChessDuelBackend.Games.GameServer
  alias ChessDuelBackendWeb.GameChannel
  alias ChessDuelBackendWeb.GamesChannel
  alias ChessDuelBackendWeb.GuestMatchmakingChannel
  alias ChessDuelBackendWeb.MatchmakingChannel
  alias ChessDuelBackendWeb.PrivateRoomChannel
  alias ChessDuelBackendWeb.UserSocket

  test "aceita token valido e associa o id real do usuario" do
    {:ok, user} =
      Accounts.register_user(%{
        email: "socket@example.com",
        nickname: "socket_player",
        password: "password1234"
      })

    user = confirm_user!(user)
    token = Accounts.generate_user_api_token(user)

    assert {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})
    assert socket.assigns.user_id == user.id
    assert UserSocket.id(socket) == "users_socket:#{user.id}"
  end

  test "recusa token ausente ou invalido" do
    assert :error = Phoenix.ChannelTest.connect(UserSocket, %{})
    assert :error = Phoenix.ChannelTest.connect(UserSocket, %{"token" => "invalid"})
  end

  test "aceita token temporario e identifica o socket como convidado" do
    %{token: token, guest: guest} = Guest.new()

    assert {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})
    assert socket.assigns.identity_type == :guest
    assert socket.assigns.user_id == guest.id
    assert UserSocket.id(socket) == "guests_socket:#{guest.id}"
  end

  test "convidado nao entra no lobby nem no matchmaking por rating" do
    %{token: token, guest: guest} = Guest.new()
    {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})

    assert {:error, %{reason: "registered_users_only"}} =
             Phoenix.ChannelTest.subscribe_and_join(socket, GamesChannel, "games:lobby")

    assert {:error, %{reason: "registered_users_only"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               MatchmakingChannel,
               "matchmaking:#{guest.id}"
             )
  end

  test "usuario autenticado nao entra na fila exclusiva de convidados" do
    user = register_user("guest-queue-block@example.com", "guest_queue_block")

    {:ok, socket} =
      Phoenix.ChannelTest.connect(UserSocket, %{
        "token" => Accounts.generate_user_api_token(user)
      })

    assert {:error, %{reason: "guests_only"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               GuestMatchmakingChannel,
               "guest_matchmaking:#{user.id}"
             )
  end

  test "MatchmakingChannel aceita somente o topico do usuario autenticado" do
    user = register_user("matchmaking-socket@example.com", "matchmaking_socket")

    {:ok, socket} =
      Phoenix.ChannelTest.connect(UserSocket, %{
        "token" => Accounts.generate_user_api_token(user)
      })

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               MatchmakingChannel,
               "matchmaking:outro-usuario"
             )

    assert {:ok, _reply, channel} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               MatchmakingChannel,
               "matchmaking:#{user.id}"
             )

    ref = Phoenix.ChannelTest.push(channel, "join_queue", %{"time_control" => "blitz_3_0"})
    Phoenix.ChannelTest.assert_reply(ref, :ok, %{time_control: %{id: "blitz_3_0"}})

    ref = Phoenix.ChannelTest.push(channel, "leave_queue", %{})
    Phoenix.ChannelTest.assert_reply(ref, :ok)
  end

  test "PrivateRoomChannel cria e inicia sala para dois usuarios autenticados" do
    creator = register_user("private-creator@example.com", "private_creator")
    opponent = register_user("private-opponent@example.com", "private_opponent")
    creator_socket = connect_user(creator)
    opponent_socket = connect_user(opponent)

    assert {:ok, _reply, creator_channel} =
             Phoenix.ChannelTest.subscribe_and_join(
               creator_socket,
               PrivateRoomChannel,
               "private_rooms:#{creator.id}"
             )

    assert {:ok, _reply, opponent_channel} =
             Phoenix.ChannelTest.subscribe_and_join(
               opponent_socket,
               PrivateRoomChannel,
               "private_rooms:#{opponent.id}"
             )

    ref =
      Phoenix.ChannelTest.push(creator_channel, "create_room", %{
        "time_control" => "blitz_5_0"
      })

    Phoenix.ChannelTest.assert_reply(ref, :ok, %{code: code, time_control: %{id: "blitz_5_0"}})

    ref = Phoenix.ChannelTest.push(opponent_channel, "join_room", %{"code" => code})
    Phoenix.ChannelTest.assert_reply(ref, :ok, %{state: :matched, game_id: game_id})

    assert {:ok, game} = GameServer.get_state(game_id)
    assert game.initial_time_ms == 300_000
    assert game.increment_ms == 0
    Process.sleep(200)
    {:ok, game_pid} = GameServer.start_or_get(game_id)
    DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, game_pid)
    Process.sleep(50)
  end

  test "PrivateRoomChannel mantem isolamento entre usuario e convidado" do
    creator = register_user("private-isolation@example.com", "private_isolation")
    creator_socket = connect_user(creator)

    assert {:ok, _reply, creator_channel} =
             Phoenix.ChannelTest.subscribe_and_join(
               creator_socket,
               PrivateRoomChannel,
               "private_rooms:#{creator.id}"
             )

    ref = Phoenix.ChannelTest.push(creator_channel, "create_room", %{"time_control" => "blitz_3_0"})
    Phoenix.ChannelTest.assert_reply(ref, :ok, %{code: code})

    %{token: token, guest: guest} = Guest.new()
    {:ok, guest_socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})

    assert {:ok, _reply, guest_channel} =
             Phoenix.ChannelTest.subscribe_and_join(
               guest_socket,
               PrivateRoomChannel,
               "private_rooms:#{guest.id}"
             )

    ref = Phoenix.ChannelTest.push(guest_channel, "join_room", %{"code" => code})
    Phoenix.ChannelTest.assert_reply(ref, :error, %{reason: "identity_mismatch"})
  end

  test "PrivateRoomChannel rejeita topico de outra identidade" do
    user = register_user("private-topic@example.com", "private_topic")

    assert {:error, %{reason: "unauthorized"}} =
             user
             |> connect_user()
             |> Phoenix.ChannelTest.subscribe_and_join(
               PrivateRoomChannel,
               "private_rooms:outra-identidade"
             )
  end

  test "GamesChannel envia desafio direto para amigo offline" do
    challenger = register_user("direct-challenge-a@example.com", "direct_challenge_a")
    challenged = register_user("direct-challenge-b@example.com", "direct_challenge_b")
    {:ok, friendship} = Social.request(challenger.id, %{"user_id" => challenged.id})
    {:ok, _friendship} = Social.act(challenged.id, friendship.id, :accept)

    assert {:ok, _state, challenger_channel} =
             challenger
             |> connect_user()
             |> Phoenix.ChannelTest.subscribe_and_join(GamesChannel, "games:lobby")

    ref =
      Phoenix.ChannelTest.push(challenger_channel, "challenge_friend", %{
        "user_id" => challenged.id,
        "time_control" => "bullet_1_0"
      })

    Phoenix.ChannelTest.assert_reply(ref, :ok)

    assert {:ok, %{challenges: [challenge]}, challenged_channel} =
             challenged
             |> connect_user()
             |> Phoenix.ChannelTest.subscribe_and_join(GamesChannel, "games:lobby")

    assert challenge.challenger.id == challenger.id
    assert challenge.challenged.id == challenged.id
    assert challenge.time_control.id == "bullet_1_0"

    ref =
      Phoenix.ChannelTest.push(challenged_channel, "decline_challenge", %{
        "challenge_id" => challenge.id
      })

    Phoenix.ChannelTest.assert_reply(ref, :ok)
  end

  test "GamesChannel recusa desafio direto para quem nao e amigo" do
    challenger = register_user("not-friend-a@example.com", "not_friend_a")
    other = register_user("not-friend-b@example.com", "not_friend_b")

    assert {:ok, _state, channel} =
             challenger
             |> connect_user()
             |> Phoenix.ChannelTest.subscribe_and_join(GamesChannel, "games:lobby")

    ref =
      Phoenix.ChannelTest.push(channel, "challenge_friend", %{
        "user_id" => other.id,
        "time_control" => "blitz_3_0"
      })

    Phoenix.ChannelTest.assert_reply(ref, :error, %{reason: "not_friends"})
  end

  test "GamesChannel envia desafio por apelido para usuario confirmado sem amizade" do
    challenger = register_user("nickname-challenge-a@example.com", "nickname_challenge_a")
    challenged = register_user("nickname-challenge-b@example.com", "nickname_challenge_b")

    assert {:ok, _state, challenger_channel} =
             challenger
             |> connect_user()
             |> Phoenix.ChannelTest.subscribe_and_join(GamesChannel, "games:lobby")

    ref =
      Phoenix.ChannelTest.push(challenger_channel, "challenge_user", %{
        "user_id" => challenged.id,
        "time_control" => "rapid_10_0"
      })

    Phoenix.ChannelTest.assert_reply(ref, :ok, %{challenge: %{id: challenge_id}})

    assert {:ok, %{challenges: [challenge]}, challenged_channel} =
             challenged
             |> connect_user()
             |> Phoenix.ChannelTest.subscribe_and_join(GamesChannel, "games:lobby")

    assert challenge.challenger.id == challenger.id
    assert challenge.challenged.id == challenged.id
    assert challenge.time_control.id == "rapid_10_0"
    assert challenge.id == challenge_id

    ref =
      Phoenix.ChannelTest.push(challenged_channel, "cancel_challenge", %{
        "challenge_id" => challenge.id
      })

    Phoenix.ChannelTest.assert_reply(ref, :error, %{reason: "not_challenger"})

    ref =
      Phoenix.ChannelTest.push(challenger_channel, "cancel_challenge", %{
        "challenge_id" => challenge.id
      })

    Phoenix.ChannelTest.assert_reply(ref, :ok)
  end

  test "GameChannel usa ids reais e preserva a cor na reconexao" do
    white = register_user("white@example.com", "white_player")
    black = register_user("black@example.com", "black_player")
    game_id = "authenticated-game-#{System.unique_integer([:positive])}"

    {:ok, white_socket} =
      Phoenix.ChannelTest.connect(UserSocket, %{"token" => Accounts.generate_user_api_token(white)})

    {:ok, black_socket} =
      Phoenix.ChannelTest.connect(UserSocket, %{"token" => Accounts.generate_user_api_token(black)})

    assert {:ok, %{player_color: "white", white_player_id: white_id}, _channel} =
             Phoenix.ChannelTest.subscribe_and_join(white_socket, GameChannel, "game:#{game_id}")

    assert white_id == white.id

    assert {:ok, %{player_color: "black", black_player_id: black_id}, _channel} =
             Phoenix.ChannelTest.subscribe_and_join(black_socket, GameChannel, "game:#{game_id}")

    assert black_id == black.id

    assert {:ok, %{player_color: "white"}, _channel} =
             Phoenix.ChannelTest.subscribe_and_join(white_socket, GameChannel, "game:#{game_id}")

    # Aguarda a fila assincrona de persistencia antes de encerrar o owner do SQL Sandbox.
    Process.sleep(500)
    {:ok, game_pid} = GameServer.start_or_get(game_id)
    DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, game_pid)
    Process.sleep(100)
  end

  defp register_user(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{
        email: email,
        nickname: nickname,
        password: "password1234"
      })

    confirm_user!(user)
  end

  defp connect_user(user) do
    {:ok, socket} =
      Phoenix.ChannelTest.connect(UserSocket, %{
        "token" => Accounts.generate_user_api_token(user)
      })

    socket
  end

  defp confirm_user!(user) do
    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end
end
