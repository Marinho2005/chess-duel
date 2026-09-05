defmodule ChessDuelBackend.Broadcasts.LichessClient do
  @moduledoc false

  alias ChessDuelBackend.Broadcasts.ReqHttpClient
  alias ChessDuelBackend.ChessValidator

  @base_url "https://lichess.org"

  def fetch_live_games(opts \\ []) do
    http = Keyword.get(opts, :http_client, ReqHttpClient)
    max_rounds = Keyword.get(opts, :max_rounds, configured(:max_rounds, 4))

    with {:ok, body} <- get(http, "/api/broadcast?live=true&nb=#{max_rounds}"),
         {:ok, broadcasts} <- decode_ndjson(body) do
      broadcasts
      |> ongoing_rounds()
      |> Enum.take(max_rounds)
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, games} ->
        case fetch_round(http, item) do
          {:ok, round_games} -> {:cont, {:ok, games ++ round_games}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp fetch_round(http, %{tour: tour, round: round}) do
    json_path = "/api/broadcast/#{tour["slug"]}/#{round["slug"]}/#{round["id"]}"
    pgn_path = "/api/broadcast/round/#{round["id"]}.pgn?clocks=false&comments=false"

    with {:ok, json_body} <- get(http, json_path, "application/json"),
         {:ok, round_data} <- Jason.decode(json_body),
         true <- valid_round?(round_data),
         {:ok, pgn} <- get(http, pgn_path, "application/x-chess-pgn"),
         {:ok, parsed_games} <- ChessValidator.parse_pgn(pgn) do
      {:ok, normalize_round(round_data, parsed_games, tour)}
    else
      false -> {:error, :invalid_response}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_round(
         %{"tour" => tour, "round" => round, "games" => games},
         parsed_games,
         source_tour
       ) do
    parsed_by_id =
      Map.new(parsed_games, fn parsed ->
        {parsed |> get_in(["headers", "GameURL"]) |> game_id_from_url(), parsed}
      end)

    games
    |> Enum.filter(&(&1["status"] == "*"))
    |> Enum.flat_map(fn game ->
      with id when is_binary(id) <- game["id"],
           %{} = parsed <- parsed_by_id[id],
           [white, black | _] <- game["players"] do
        moves = parsed["moves"] || []
        [normalize_game(id, tour, round, game, white, black, parsed, moves, source_tour)]
      else
        _ -> []
      end
    end)
  end

  defp normalize_game(id, tour, round, game, white, black, parsed, moves, source_tour) do
    headers = parsed["headers"] || %{}
    last_move = List.last(moves)

    %{
      game_id: id,
      tournament_id: source_tour["id"] || source_tour["slug"] || slugify(tour["name"]),
      tournament: tour["name"],
      tournament_image: source_tour["image"] || tour["image"],
      round: round["name"],
      white: player(white, headers, "White"),
      black: player(black, headers, "Black"),
      fen: game["fen"] || parsed["fen"],
      last_move: last_move,
      moves: moves,
      lichess_url: headers["GameURL"] || "#{round["url"]}/#{id}"
    }
  end

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp player(player, headers, color) do
    %{
      name: player["name"] || headers[color] || "",
      title: player["title"] || headers["#{color}Title"],
      rating: integer(player["rating"] || headers["#{color}Elo"]),
      country_code: player["fed"] || headers["#{color}Country"]
    }
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp ongoing_rounds(broadcasts) do
    for %{"tour" => tour, "rounds" => rounds} <- broadcasts,
        round <- rounds,
        round["ongoing"] == true,
        do: %{tour: tour, round: round}
  end

  defp decode_ndjson(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, rows} ->
      case Jason.decode(line) do
        {:ok, row} -> {:cont, {:ok, [row | rows]}}
        _ -> {:halt, {:error, :invalid_response}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp valid_round?(%{"tour" => %{}, "round" => %{}, "games" => games}) when is_list(games),
    do: true

  defp valid_round?(_), do: false

  defp game_id_from_url(url) when is_binary(url),
    do: url |> String.trim_trailing("/") |> String.split("/") |> List.last()

  defp game_id_from_url(_), do: nil

  defp get(http, path, accept \\ "application/x-ndjson") do
    url = configured(:base_url, @base_url) <> path

    headers = [
      {"accept", accept},
      {"user-agent", configured(:user_agent, "ChessDuel/0.1 (broadcast integration)")}
    ]

    headers =
      case configured(:token, nil) do
        token when is_binary(token) and token != "" ->
          [{"authorization", "Bearer #{token}"} | headers]

        _ ->
          headers
      end

    case http.get(url, headers: headers, timeout: configured(:timeout_ms, 5_000)) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp configured(key, default),
    do:
      Application.get_env(:chess_duel_backend, :lichess_broadcasts, []) |> Keyword.get(key, default)
end
