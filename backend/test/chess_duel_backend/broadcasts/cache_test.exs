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

  test "broadcasts clock synchronization even without a new move" do
    first = Map.put(game("same", []), :live_clock, %{think_time_ms: 10_000, sampled_at_ms: 100_000})
    second = %{first | live_clock: %{think_time_ms: 30_000, sampled_at_ms: 120_000}}
    {:ok, responses} = Agent.start_link(fn -> [{:ok, [first]}, {:ok, [second]}] end)
    client = fn -> Agent.get_and_update(responses, fn [next | rest] -> {next, rest} end) end
    cache = start_supervised!({Cache, name: nil, client: client, auto_refresh: false})
    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "broadcast_watch:game-1")
    assert :ok = Cache.refresh(cache)
    assert :ok = Cache.refresh(cache)

    assert_receive %{
      event: "broadcast_move",
      payload: %{fen: "same", live_clock: %{think_time_ms: 30_000}}
    }
  end

  test "groups live games by tournament without mixing them" do
    open = game("open-fen", [])

    masters = %{
      game("masters-fen", [])
      | game_id: "game-2",
        tournament_id: "masters",
        tournament: "Masters"
    }

    client = fn -> {:ok, [open, masters]} end
    {:ok, cache} = start_supervised({Cache, name: nil, client: client, auto_refresh: false})

    assert :ok = Cache.refresh(cache)

    assert [
             %{tournament_id: "masters", name: "Masters", image_url: nil, live_games: 1},
             %{tournament_id: "open", name: "Open", image_url: nil, live_games: 1}
           ] = Cache.list_tournaments(cache)

    assert [%{game_id: "game-1"}] = Cache.list_tournament_games("open", cache)
    assert [%{game_id: "game-2"}] = Cache.list_tournament_games("masters", cache)
    assert [] = Cache.list_tournament_games("missing", cache)
  end

  test "keeps catalog entries without games and preserves a failed round snapshot" do
    previous = Map.put(game("start", []), :round_id, "round123")

    tournaments = [
      %{tournament_id: "open", name: "Open", image_url: nil, live_games: nil},
      %{tournament_id: "other", name: "Other", image_url: nil, live_games: nil}
    ]

    snapshot = %{
      games: [],
      tournaments: tournaments,
      failed_rounds: ["round123"],
      rate_limited: false
    }

    {:ok, responses} = Agent.start_link(fn -> [{:ok, [previous]}, {:ok, snapshot}] end)
    client = fn -> Agent.get_and_update(responses, fn [next | rest] -> {next, rest} end) end
    cache = start_supervised!({Cache, name: nil, client: client, auto_refresh: false})
    assert :ok = Cache.refresh(cache)
    assert :ok = Cache.refresh(cache)
    assert [^previous] = Cache.list_games(cache)

    assert [%{tournament_id: "open", live_games: 1}, %{tournament_id: "other", live_games: nil}] =
             Cache.list_tournaments(cache)
  end

  test "automatic refresh does not block catalog reads" do
    parent = self()

    client = fn ->
      send(parent, {:refresh_started, self()})

      receive do
        :release -> {:ok, []}
      end
    end

    cache = start_supervised!({Cache, name: nil, client: client, auto_refresh: false})
    send(cache, :refresh)
    assert_receive {:refresh_started, worker}
    assert [] = Cache.list_tournaments(cache)
    send(worker, :release)
  end

  defp game(fen, moves),
    do: %{
      game_id: "game-1",
      tournament_id: "open",
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
