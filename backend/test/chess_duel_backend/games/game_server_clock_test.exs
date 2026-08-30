defmodule ChessDuelBackend.Games.GameServerClockTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Games.{GameServer, TimeControl}

  test "aplica incremento Fischer depois de descontar o tempo do lance valido" do
    game_id = Ecto.UUID.generate()
    white_id = Ecto.UUID.generate()
    black_id = Ecto.UUID.generate()
    {:ok, control} = TimeControl.fetch("blitz_5_3")

    cleanup_game(game_id)
    assert {:ok, state} = GameServer.reserve_players(game_id, white_id, black_id, control)
    assert state.white_time_remaining_ms == 300_000
    assert state.increment_ms == 3_000

    assert {:ok, after_white_first} = GameServer.make_move(game_id, "e2", "e4", white_id)
    assert after_white_first.white_time_remaining_ms <= 303_000
    assert after_white_first.white_time_remaining_ms > 302_500

    assert {:ok, _after_black} = GameServer.make_move(game_id, "e7", "e5", black_id)
    Process.sleep(30)

    assert {:ok, after_white_second} = GameServer.make_move(game_id, "g1", "f3", white_id)
    assert after_white_second.white_time_remaining_ms < 306_000
    assert after_white_second.white_time_remaining_ms > 305_500
  end

  test "formato Bullet 1+0 nao adiciona incremento" do
    game_id = Ecto.UUID.generate()
    white_id = Ecto.UUID.generate()
    black_id = Ecto.UUID.generate()
    {:ok, control} = TimeControl.fetch("bullet_1_0")

    cleanup_game(game_id)
    assert {:ok, state} = GameServer.reserve_players(game_id, white_id, black_id, control)
    assert state.white_time_remaining_ms == 60_000
    assert state.increment_ms == 0

    assert {:ok, after_move} = GameServer.make_move(game_id, "e2", "e4", white_id)
    assert after_move.white_time_remaining_ms <= 60_000
    assert after_move.white_time_remaining_ms > 59_500
  end

  defp cleanup_game(game_id) do
    on_exit(fn ->
      case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
        [] -> :ok
      end

      Process.sleep(50)
    end)
  end
end
