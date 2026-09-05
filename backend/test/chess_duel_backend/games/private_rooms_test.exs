defmodule ChessDuelBackend.Games.PrivateRoomsTest do
  use ChessDuelBackend.DataCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games
  alias ChessDuelBackend.Games.{GameServer, PrivateRooms}
  alias ChessDuelBackend.Repo

  test "cria sala autenticada, inicia a partida no formato escolhido e a marca como cheia" do
    creator = user()
    opponent = user()

    assert {:ok, room} = PrivateRooms.create(creator, :user, "blitz_5_0")
    assert room.status == :waiting
    assert room.time_control.id == "blitz_5_0"

    assert {:ok, :matched, match} = PrivateRooms.join(room.code, opponent, :user)
    assert match.time_control.id == "blitz_5_0"
    assert match.guest_game == false

    assert {:ok, game} = GameServer.get_state(match.game_id)
    assert game.initial_time_ms == 300_000
    assert game.increment_ms == 0

    assert MapSet.new([game.white_player_id, game.black_player_id]) ==
             MapSet.new([creator.id, opponent.id])

    assert Games.get_game_by_game_id(match.game_id)

    assert {:error, :room_full} = PrivateRooms.join(room.code, user(), :user)
    stop_game(match.game_id)
  end

  test "criador pode reabrir o link sem ocupar a segunda vaga" do
    creator = user()
    assert {:ok, room} = PrivateRooms.create(creator, :user, "blitz_3_0")
    assert {:ok, :waiting, _room} = PrivateRooms.join(room.code, creator, :user)
    assert {:ok, :matched, match} = PrivateRooms.join(room.code, user(), :user)
    stop_game(match.game_id)
  end

  test "isola salas autenticadas e convidadas" do
    assert {:ok, user_room} = PrivateRooms.create(user(), :user, "blitz_3_0")
    assert {:error, :identity_mismatch} = PrivateRooms.join(user_room.code, guest(), :guest)

    assert {:ok, guest_room} = PrivateRooms.create(guest(), :guest, "rapid_10_0")
    assert {:error, :identity_mismatch} = PrivateRooms.join(guest_room.code, user(), :user)
  end

  test "partida privada entre convidados nao e persistida" do
    assert {:ok, room} = PrivateRooms.create(guest(), :guest, "bullet_1_0")
    assert {:ok, :matched, match} = PrivateRooms.join(room.code, guest(), :guest)
    assert match.guest_game
    assert Games.get_game_by_game_id(match.game_id) == nil
  end

  test "codigo inexistente retorna erro claro" do
    assert {:error, :room_not_found} = PrivateRooms.join("INEXISTE", user(), :user)
  end

  test "remove sala quando o temporizador de expiracao dispara" do
    assert {:ok, room} = PrivateRooms.create(user(), :user, "blitz_3_0")
    send(Process.whereis(PrivateRooms), {:expire, room.code})
    assert_eventually(fn -> PrivateRooms.get(room.code) == {:error, :room_not_found} end)
  end

  defp user do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        email: "private-room-#{suffix}@example.com",
        nickname: "private_room_#{suffix}",
        password: "password1234"
      })

    user
    |> User.confirm_changeset()
    |> Repo.update!()
  end

  defp guest do
    suffix = System.unique_integer([:positive])
    %{id: "guest-#{suffix}", nickname: "Convidado-#{suffix}", guest: true}
  end

  defp assert_eventually(fun, attempts \\ 20)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if fun.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp stop_game(game_id) do
    Process.sleep(200)
    {:ok, pid} = GameServer.start_or_get(game_id)
    DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
    Process.sleep(50)
  end
end
