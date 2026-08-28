defmodule ChessDuelBackend.Games.GuestMatchmakerTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Games.{GameServer, GuestMatchmaker}

  test "pareia dois convidados em memoria e nunca persiste nem calcula rating" do
    first = guest("first")
    second = guest("second")
    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "guest_matchmaking:#{first.id}")

    assert {:ok, :waiting} = GuestMatchmaker.join_queue(first)
    assert {:ok, :matched} = GuestMatchmaker.join_queue(second)
    assert [] = GuestMatchmaker.waiting_guests()

    assert_receive %Phoenix.Socket.Broadcast{
                     event: "match_found",
                     payload: %{game_id: game_id, guest_game: true}
                   },
                   1_000

    assert {:ok, state} = GameServer.get_state(game_id)
    assert state.game_type == :guest
    assert state.white_player.guest
    assert state.black_player.guest
    assert Games.get_game_by_game_id(game_id) == nil

    assert {:error, :identity_mismatch} =
             GameServer.player_connected(game_id, Ecto.UUID.generate(), :user)

    assert {:ok, _state} = play_fools_mate(state)
    Process.sleep(100)

    assert {:ok, finished} = GameServer.get_state(game_id)
    assert finished.status == "finished"
    assert finished.game_over_reason == "checkmate"
    assert Games.get_game_by_game_id(game_id) == nil
  after
    GuestMatchmaker.leave_queue("guest-first")
    GuestMatchmaker.leave_queue("guest-second")
  end

  test "recusa uma identidade autenticada na fila de convidados" do
    assert {:error, :guests_only} =
             GuestMatchmaker.join_queue(%{id: Ecto.UUID.generate(), nickname: "Usuario"})
  end

  test "convidado nao cria partida persistida ao manipular um game_id" do
    game_id = Ecto.UUID.generate()

    assert {:error, :game_not_found} =
             GameServer.player_connected(game_id, "guest-manipulated", :guest)

    assert Games.get_game_by_game_id(game_id) == nil
  end

  defp play_fools_mate(state) do
    white = state.white_player_id
    black = state.black_player_id

    with {:ok, _} <- GameServer.make_move(state.game_id, "f2", "f3", white),
         {:ok, _} <- GameServer.make_move(state.game_id, "e7", "e5", black),
         {:ok, _} <- GameServer.make_move(state.game_id, "g2", "g4", white) do
      GameServer.make_move(state.game_id, "d8", "h4", black)
    end
  end

  defp guest(suffix) do
    %{id: "guest-#{suffix}", nickname: "Convidado-#{suffix}", guest: true}
  end
end
