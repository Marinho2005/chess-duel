defmodule ChessDuelBackendWeb.BroadcastWatchChannelTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  require Phoenix.ChannelTest

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Broadcasts.Cache
  alias ChessDuelBackend.Repo
  alias ChessDuelBackendWeb.{BroadcastWatchChannel, UserSocket}

  setup do
    original = :sys.get_state(Cache)
    on_exit(fn -> :sys.replace_state(Cache, fn _ -> original end) end)
    :ok
  end

  test "joins an existing broadcast with its full snapshot and receives moves" do
    game = sample_game()
    :sys.replace_state(Cache, &%{&1 | games: %{game.game_id => game}})
    socket = authenticated_socket()

    assert {:ok, ^game, channel} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               BroadcastWatchChannel,
               "broadcast_watch:game-1"
             )

    ChessDuelBackendWeb.Endpoint.broadcast("broadcast_watch:game-1", "broadcast_move", %{
      game_id: "game-1",
      fen: "new",
      last_move: nil,
      moves: []
    })

    Phoenix.ChannelTest.assert_push("broadcast_move", %{fen: "new"})
    Phoenix.ChannelTest.leave(channel)
  end

  test "rejects a missing game" do
    assert {:error, %{reason: "broadcast_not_found"}} =
             authenticated_socket()
             |> Phoenix.ChannelTest.subscribe_and_join(
               BroadcastWatchChannel,
               "broadcast_watch:missing"
             )
  end

  defp authenticated_socket do
    {:ok, user} =
      Accounts.register_user(%{
        email: "broadcast-#{System.unique_integer([:positive])}@example.com",
        nickname: "watcher_#{System.unique_integer([:positive])}",
        password: "password1234"
      })

    user = user |> User.confirm_changeset() |> Repo.update!()

    {:ok, socket} =
      Phoenix.ChannelTest.connect(UserSocket, %{"token" => Accounts.generate_user_api_token(user)})

    socket
  end

  defp sample_game,
    do: %{
      game_id: "game-1",
      tournament: "Open",
      round: "R1",
      white: %{name: "W", title: "GM", rating: 2500, country_code: "BRA"},
      black: %{name: "B", title: nil, rating: 2400, country_code: "USA"},
      fen: "start",
      last_move: nil,
      moves: [],
      lichess_url: "https://lichess.org"
    }
end
