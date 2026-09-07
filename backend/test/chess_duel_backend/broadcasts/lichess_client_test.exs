defmodule ChessDuelBackend.Broadcasts.LichessClientTest do
  use ExUnit.Case, async: false

  alias ChessDuelBackend.Broadcasts.LichessClient

  defmodule FakeHTTP do
    def get(url, _options) do
      Process.put(:requested_urls, [url | Process.get(:requested_urls, [])])

      cond do
        String.contains?(url, "/api/broadcast/top?") -> Process.get(:official_response)
        String.ends_with?(url, ".pgn?clocks=false&comments=false") -> Process.get(:pgn_response)
        true -> Process.get(:round_response)
      end
    end
  end

  setup do
    Process.put(:official_response, {:ok, %{status: 200, body: official_ndjson()}})
    Process.put(:round_response, {:ok, %{status: 200, body: Jason.encode!(round_json())}})
    Process.put(:pgn_response, {:ok, %{status: 200, body: pgn()}})
    :ok
  end

  test "normalizes official round JSON and PGN into the stable contract" do
    assert {:ok, [game]} = LichessClient.fetch_live_games(http_client: FakeHTTP)
    assert game.game_id == "AbCd1234"
    assert game.tournament_id == "example-open"
    assert game.tournament_image == "https://lichess1.org/broadcast/example.webp"
    assert game.tournament == "Example Open"
    assert game.round == "Round 3"
    assert game.white == %{name: "White Player", title: "GM", rating: 2640, country_code: "BRA"}
    assert game.black == %{name: "Black Player", title: "IM", rating: 2512, country_code: "USA"}
    assert Enum.map(game.moves, & &1["san"]) == ["e4", "e5", "Nf3"]
    assert game.last_move["from"] == "g1"
    assert game.lichess_url =~ "/AbCd1234"
  end

  test "returns an empty list when no official broadcast is live" do
    Process.put(:official_response, {:ok, %{status: 200, body: Jason.encode!(%{active: []})}})
    assert {:ok, []} = LichessClient.fetch_live_games(http_client: FakeHTTP)
  end

  test "maps HTTP errors, timeout and invalid responses without external calls" do
    Process.put(:official_response, {:ok, %{status: 503, body: ""}})
    assert {:error, {:http_error, 503}} = LichessClient.fetch_live_games(http_client: FakeHTTP)

    Process.put(:official_response, {:error, :timeout})
    assert {:error, :timeout} = LichessClient.fetch_live_games(http_client: FakeHTTP)

    Process.put(:official_response, {:ok, %{status: 200, body: "not-json\n"}})
    assert {:error, :invalid_response} = LichessClient.fetch_live_games(http_client: FakeHTTP)
  end

  defp official_ndjson do
    Jason.encode!(%{
      "active" => [
        %{
          "tour" => %{
            "id" => "example-open",
            "name" => "Example Open",
            "slug" => "example-open",
            "image" => "https://lichess1.org/broadcast/example.webp"
          },
          "round" => %{
            "id" => "round123",
            "name" => "Round 3",
            "slug" => "round-3",
            "ongoing" => true
          }
        }
      ]
    })
  end

  test "loads more than four live tournaments and excludes upcoming rounds" do
    item = Jason.decode!(official_ndjson())["active"] |> hd()
    live = for n <- 1..7, do: put_in(item, ["tour", "id"], "tour#{n}")
    upcoming = put_in(item, ["round", "ongoing"], false)

    Process.put(
      :official_response,
      {:ok, %{status: 200, body: Jason.encode!(%{active: live ++ [upcoming]})}}
    )

    assert {:ok, snapshot} = LichessClient.fetch_live_snapshot(http_client: FakeHTTP)
    assert length(snapshot.tournaments) == 7
    assert length(snapshot.games) == 7
    assert Enum.all?(Process.get(:requested_urls), &(not String.contains?(&1, "nb=")))
  end

  test "retains tournament catalog on a round failure and stops requests after rate limiting" do
    item = Jason.decode!(official_ndjson())["active"] |> hd()

    Process.put(
      :official_response,
      {:ok, %{status: 200, body: Jason.encode!(%{active: [item, item]})}}
    )

    Process.put(:round_response, {:ok, %{status: 429, body: ""}})

    assert {:ok, %{tournaments: [_, _], games: [], rate_limited: true}} =
             LichessClient.fetch_live_snapshot(http_client: FakeHTTP)

    assert length(Process.get(:requested_urls)) == 2
  end

  test "previous rounds include finished games and their result" do
    round = put_in(round_json(), ["games", Access.at(0), "status"], "1-0")
    Process.put(:round_response, {:ok, %{status: 200, body: Jason.encode!(round)}})

    assert {:ok, [%{result: "1-0", round_id: "round123", moves: [_, _, _]}]} =
             LichessClient.fetch_round_games("round123", http_client: FakeHTTP)

    assert {:ok, []} = LichessClient.fetch_live_games(http_client: FakeHTTP)
  end

  test "rejects invalid round IDs before making external requests" do
    assert {:error, :not_found} = LichessClient.fetch_round_games("../x", http_client: FakeHTTP)
    assert Process.get(:requested_urls, []) == []
  end

  defp round_json do
    %{
      "tour" => %{"name" => "Example Open"},
      "round" => %{
        "id" => "round123",
        "name" => "Round 3",
        "url" => "https://lichess.org/broadcast/example-open/round-3/round123"
      },
      "games" => [
        %{
          "id" => "AbCd1234",
          "status" => "*",
          "fen" => "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          "players" => [
            %{"name" => "White Player", "title" => "GM", "rating" => 2640, "fed" => "BRA"},
            %{"name" => "Black Player", "title" => "IM", "rating" => 2512, "fed" => "USA"}
          ]
        }
      ]
    }
  end

  defp pgn do
    """
    [Event "Example Open"]
    [Site "https://lichess.org/broadcast/example-open/round-3/round123/AbCd1234"]
    [GameURL "https://lichess.org/broadcast/example-open/round-3/round123/AbCd1234"]
    [White "White Player"]
    [Black "Black Player"]
    [Result "*"]

    1. e4 e5 2. Nf3 *
    """
  end
end
