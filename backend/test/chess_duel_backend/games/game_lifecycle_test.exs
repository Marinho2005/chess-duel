defmodule ChessDuelBackend.Games.GameLifecycleTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Games.{GameServer, TimeControl}

  setup do
    previous = Application.get_env(:chess_duel_backend, :game_preparation_ms, 0)
    on_exit(fn -> Application.put_env(:chess_duel_backend, :game_preparation_ms, previous) end)
    :ok
  end

  test "relógios congelam na preparação e abort é permitido" do
    Application.put_env(:chess_duel_backend, :game_preparation_ms, 10_000)
    {game_id, white, black} = ids()
    {:ok, control} = TimeControl.fetch("bullet_1_0")
    assert {:ok, state} = GameServer.reserve_players(game_id, white, black, control)
    Process.sleep(25)
    assert {:ok, snapshot} = GameServer.get_state(game_id)
    assert snapshot.status == "waiting"
    assert snapshot.white_time_remaining_ms == state.white_time_remaining_ms
    assert {:error, :game_preparing} = GameServer.make_move(game_id, "e2", "e4", white)
    assert {:ok, aborted} = GameServer.abort_game(game_id, white)
    assert aborted.status == "finished"
    assert aborted.game_over_reason == "aborted"
    cleanup(game_id)
  end

  test "servidor ativa a partida e rejeita abort tardio" do
    Application.put_env(:chess_duel_backend, :game_preparation_ms, 30)
    {game_id, white, black} = ids()
    assert {:ok, _} = GameServer.reserve_players(game_id, white, black)
    Process.sleep(45)
    assert {:ok, state} = GameServer.get_state(game_id)
    assert state.status == "in_progress"
    assert {:error, :abort_unavailable} = GameServer.abort_game(game_id, white)
    cleanup(game_id)
  end

  test "desistência finaliza uma única vez e entrega vitória ao adversário" do
    {game_id, white, black} = ids()
    assert {:ok, _} = GameServer.reserve_players(game_id, white, black)
    assert {:ok, state} = GameServer.resign(game_id, white)
    assert state.status == "finished"
    assert state.game_over_reason == "resignation"
    assert state.winner_player_id == black
    assert {:error, :resign_unavailable} = GameServer.resign(game_id, white)
    cleanup(game_id)
  end

  defp ids, do: {Ecto.UUID.generate(), Ecto.UUID.generate(), Ecto.UUID.generate()}

  defp cleanup(game_id) do
    case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
      [] -> :ok
    end
  end
end
