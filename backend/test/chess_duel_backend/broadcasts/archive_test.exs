defmodule ChessDuelBackend.Broadcasts.ArchiveTest do
  use ExUnit.Case, async: false
  alias ChessDuelBackend.Broadcasts.Archive

  test "coalesces concurrent requests and serves completed rounds from cache" do
    parent = self()

    fetch = fn key ->
      send(parent, {:fetch, key, self()})

      receive do
        :release -> {:ok, [%{result: "1-0"}]}
      end
    end

    server = start_supervised!({Archive, name: :archive_test, fetch: fetch})
    first = Task.async(fn -> Archive.round_games("round123", server) end)
    assert_receive {:fetch, {:round, "round123"}, worker}
    second = Task.async(fn -> Archive.round_games("round123", server) end)
    send(worker, :release)
    assert {:ok, [%{result: "1-0"}]} = Task.await(first)
    assert {:ok, [%{result: "1-0"}]} = Task.await(second)
    assert {:ok, [%{result: "1-0"}]} = Archive.round_games("round123", server)
    refute_receive {:fetch, _, _}
  end

  test "backs off after a Lichess rate limit" do
    parent = self()

    fetch = fn key ->
      send(parent, {:fetch, key})
      {:error, :rate_limited}
    end

    server = start_supervised!({Archive, name: :archive_test, fetch: fetch})
    assert {:error, :rate_limited} = Archive.round_games("round123", server)
    assert_receive {:fetch, {:round, "round123"}}
    assert {:error, :rate_limited} = Archive.round_games("round456", server)
    refute_receive {:fetch, _}
  end
end
