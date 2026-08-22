defmodule ChessDuelBackendWeb.UserSocketTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  require Phoenix.ChannelTest

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games.GameServer
  alias ChessDuelBackendWeb.GameChannel
  alias ChessDuelBackendWeb.UserSocket

  test "aceita token valido e associa o id real do usuario" do
    {:ok, user} =
      Accounts.register_user(%{
        email: "socket@example.com",
        nickname: "socket_player",
        password: "password1234"
      })

    token = Accounts.generate_user_api_token(user)

    assert {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => token})
    assert socket.assigns.user_id == user.id
    assert UserSocket.id(socket) == "users_socket:#{user.id}"
  end

  test "recusa token ausente ou invalido" do
    assert :error = Phoenix.ChannelTest.connect(UserSocket, %{})
    assert :error = Phoenix.ChannelTest.connect(UserSocket, %{"token" => "invalid"})
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

    user
  end
end
