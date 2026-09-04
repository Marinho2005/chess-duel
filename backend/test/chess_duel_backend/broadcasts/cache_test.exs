defmodule ChessDuelBackend.Broadcasts.CacheTest do
  use ExUnit.Case, async: false

  alias ChessDuelBackend.Broadcasts.Cache

  test "keeps the last valid snapshot, emits only real moves, and removes finished games" do
    game = game("start", [])
    moved = game("after", [%{san: "e4", from: "e2", to: "e4", promotion: nil}])

    {:ok, responses} =
      Agent.start_link(fn ->
        [{:ok, [game]}, {:error, :timeout}, {:ok, [game]}, {:ok, [moved]}, {:ok, []}]
      end)

    client = fn -> Agent.get_and_update(responses, fn [next | rest] -> {next, rest} end) end
    {:ok, cache} = start_supervised({Cache, name: nil, client: client, auto_refresh: false})

    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "broadcast_watch:game-1")
    assert :ok = Cache.refresh(cache)
    assert [^game] = Cache.list_games(cache)
    refute_receive %{event: "broadcast_move"}

    assert {:error, :timeout} = Cache.refresh(cache)
    assert [^game] = Cache.list_games(cache)
    assert :ok = Cache.refresh(cache)
    refute_receive %{event: "broadcast_move"}

    assert :ok = Cache.refresh(cache)
    assert_receive %{event: "broadcast_move", payload: %{fen: "after", moves: [_]}}
    assert :ok = Cache.refresh(cache)
    assert_receive %{event: "broadcast_ended", payload: %{game_id: "game-1"}}
    assert [] = Cache.list_games(cache)
  end

  defp game(fen, moves),
    do: %{
      game_id: "game-1",
      tournament: "Open",
      round: "R1",
      white: %{},
      black: %{},
      fen: fen,
      last_move: List.last(moves),
      moves: moves,
      lichess_url: "https://lichess.org"
    }
end
