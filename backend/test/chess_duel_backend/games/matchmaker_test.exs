defmodule ChessDuelBackend.Games.MatchmakerTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Games.{GameServer, Matchmaker, TimeControl}

  setup do
    clear_matchmaking_keys()
    on_exit(&clear_matchmaking_keys/0)
    :ok
  end

  test "mantem jogador sozinho na fila e permite cancelamento" do
    user = register_user("queue-alone@example.com", "queue_alone")

    assert {:ok, %{time_control: %{id: "blitz_3_0"}}} =
             Matchmaker.join_queue(user, "blitz_3_0")

    assert {:ok, [entry]} = Matchmaker.queue_entries("blitz_3_0")
    assert entry.user_id == user.id
    assert entry.rating == user.rating

    assert :ok = Matchmaker.leave_queue(user.id)
    assert {:ok, []} = Matchmaker.queue_entries("blitz_3_0")
  end

  test "pareia ratings proximos no mesmo formato e cria GameServer configurado" do
    first = register_user("queue-first@example.com", "queue_first")
    second = register_user("queue-second@example.com", "queue_second")

    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "matchmaking:#{first.id}")
    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "matchmaking:#{second.id}")

    assert {:ok, _queue} = Matchmaker.join_queue(first, "blitz_5_0")
    assert {:ok, _queue} = Matchmaker.join_queue(second, "blitz_5_0")
    assert :ok = Matchmaker.match_now()

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "match_found",
                     payload: %{game_id: game_id, time_control: %{id: "blitz_5_0"}}
                   },
                   1_000

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "match_found",
                     payload: %{game_id: ^game_id}
                   },
                   1_000

    assert {:ok, []} = Matchmaker.queue_entries("blitz_5_0")
    assert {:ok, state} = GameServer.get_state(game_id)

    assert Enum.sort([state.white_player_id, state.black_player_id]) ==
             Enum.sort([first.id, second.id])

    assert state.initial_time_ms == 300_000
    assert state.increment_ms == 0

    stop_game(game_id)
  end

  test "nao mistura jogadores de formatos diferentes" do
    bullet = register_user("queue-bullet@example.com", "queue_bullet")
    rapid = register_user("queue-rapid@example.com", "queue_rapid")

    assert {:ok, _queue} = Matchmaker.join_queue(bullet, "bullet_1_0")
    assert {:ok, _queue} = Matchmaker.join_queue(rapid, "rapid_10_0")
    assert :ok = Matchmaker.match_now()

    assert {:ok, [_]} = Matchmaker.queue_entries("bullet_1_0")
    assert {:ok, [_]} = Matchmaker.queue_entries("rapid_10_0")
  end

  test "rejeita entrar na fila se o usuario ja estiver em uma partida ativa" do
    player1 = register_user("queue-active1@example.com", "queue_active1")
    player2 = register_user("queue-active2@example.com", "queue_active2")
    game_id = "queue-active-#{System.unique_integer([:positive])}"

    assert {:ok, _} = GameServer.reserve_players(game_id, player1.id, player2.id)

    assert {:error, {:already_in_game, ^game_id}} = Matchmaker.join_queue(player1, "blitz_3_0")
    assert {:error, {:already_in_game, ^game_id}} = Matchmaker.join_queue(player2, "blitz_3_0")

    stop_game(game_id)
  end

  defp register_user(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user
  end

  defp clear_matchmaking_keys do
    keys =
      TimeControl.all()
      |> Enum.map(&"matchmaking:queue:#{&1.id}")

    Redix.command(:valkey, ["DEL" | keys])
    :ok
  end

  defp stop_game(game_id) do
    case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
      [] -> :ok
    end

    Process.sleep(100)
  end
end
