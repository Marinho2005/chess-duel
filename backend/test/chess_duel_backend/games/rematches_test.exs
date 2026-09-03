defmodule ChessDuelBackend.Games.RematchesTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Games.{Bots, GameServer, Rematches, TimeControl}

  setup do
    previous = Application.get_env(:chess_duel_backend, :game_preparation_ms, 0)
    Application.put_env(:chess_duel_backend, :game_preparation_ms, 0)
    on_exit(fn -> Application.put_env(:chess_duel_backend, :game_preparation_ms, previous) end)
    :ok
  end

  test "dois jogadores confirmam a revanche com cores invertidas e mesmo relógio" do
    original_id = Ecto.UUID.generate()
    white = Ecto.UUID.generate()
    black = Ecto.UUID.generate()
    {:ok, control} = TimeControl.fetch("blitz_5_0")

    assert {:ok, _state} = GameServer.reserve_players(original_id, white, black, control)
    assert {:ok, _finished} = GameServer.resign(original_id, white)
    assert {:ok, %{status: "waiting"}} = Rematches.request(original_id, white)
    assert %{status: "incoming"} = Rematches.status(original_id, black)
    assert {:ok, %{status: "started", game_id: rematch_id}} = Rematches.accept(original_id, black)
    assert {:ok, rematch} = GameServer.get_state(rematch_id)
    assert rematch.white_player_id == black
    assert rematch.black_player_id == white
    assert rematch.initial_time_ms == 300_000
    assert rematch.increment_ms == 0

    assert {:ok, %{game_id: ^rematch_id}} = Rematches.accept(original_id, black)
    cleanup(original_id)
    cleanup(rematch_id)
  end

  test "bot aceita imediatamente e troca a cor do jogador" do
    original_id = Ecto.UUID.generate()
    player = Ecto.UUID.generate()
    bot = Bots.get("clark")
    {:ok, control} = TimeControl.fetch("blitz_3_0")

    assert {:ok, _state} = GameServer.reserve_bot_game(original_id, player, bot, "white", control)
    assert {:ok, _finished} = GameServer.resign(original_id, player)

    assert {:ok, %{status: "started", game_id: rematch_id}} =
             Rematches.accept_bot(original_id, player)

    assert {:ok, rematch} = GameServer.get_state(rematch_id)
    assert rematch.game_type == :bot
    assert rematch.bot_id == "clark"
    assert rematch.black_player_id == player
    assert rematch.white_player_id == Bots.player_id("clark")

    cleanup(original_id)
    cleanup(rematch_id)
  end

  test "não oferece revanche enquanto a partida continua ativa" do
    game_id = Ecto.UUID.generate()
    white = Ecto.UUID.generate()
    black = Ecto.UUID.generate()

    assert {:ok, _state} = GameServer.reserve_players(game_id, white, black)
    assert {:error, :rematch_unavailable} = Rematches.request(game_id, white)
    cleanup(game_id)
  end

  defp cleanup(game_id) do
    case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
      [] -> :ok
    end
  end
end
