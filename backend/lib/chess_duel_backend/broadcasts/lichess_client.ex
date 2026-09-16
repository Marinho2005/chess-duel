defmodule ChessDuelBackend.Broadcasts.LichessClient do
  @moduledoc false

  alias ChessDuelBackend.Broadcasts.ReqHttpClient
  alias ChessDuelBackend.Broadcasts.PgnParser

  @base_url "https://lichess.org"

  def fetch_live_games(opts \\ []) do
    with {:ok, snapshot} <- fetch_live_snapshot(opts), do: {:ok, snapshot.games}
  end

  def fetch_live_snapshot(opts \\ []) do
    http = Keyword.get(opts, :http_client, ReqHttpClient)

    with {:ok, body} <- get(http, "/api/broadcast/top?page=1", "application/json"),
         {:ok, %{"active" => active}} when is_list(active) <- Jason.decode(body) do
      live = Enum.filter(active, &(get_in(&1, ["round", "ongoing"]) == true))
      initial = %{games: [], tournaments: [], failed_rounds: [], rate_limited: false}

      snapshot =
        Enum.reduce(live, initial, fn %{"tour" => tour, "round" => round}, acc ->
          tournament = %{
            tournament_id: tour["id"],
            name: tour["name"],
            image_url: tour["image"],
            live_games: nil
          }

          acc = %{acc | tournaments: acc.tournaments ++ [tournament]}
          # Depois de um 429, preserve o catálogo e aguarde antes de consultar novamente.
          result =
            if acc.rate_limited,
              do: {:error, :rate_limited},
              else: fetch_round(http, %{tour: tour, round: round})

          case result do
            {:ok, games} ->
              %{acc | games: acc.games ++ Enum.filter(games, &(&1.result == "*"))}

            {:error, reason} ->
              %{
                acc
                | failed_rounds: [round["id"] | acc.failed_rounds],
                  rate_limited: acc.rate_limited or reason == :rate_limited
              }
          end
        end)

      {:ok, snapshot}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  def fetch_tournament(id, opts \\ []) do
    with true <- valid_id?(id),
         {:ok, body} <-
           get(
             Keyword.get(opts, :http_client, ReqHttpClient),
             "/api/broadcast/#{id}",
             "application/json"
           ),
         {:ok, %{"tour" => tour, "rounds" => rounds}} when is_list(rounds) <- Jason.decode(body) do
      {:ok,
       %{
         tournament_id: tour["id"],
         name: tour["name"],
         image_url: tour["image"],
         rounds:
           Enum.map(rounds, fn round ->
             %{
               id: round["id"],
               name: round["name"],
               ongoing: round["ongoing"] == true,
               finished: round["finishedAt"] != nil or round["finished"] == true,
               starts_at: round["startsAt"]
             }
           end)
       }}
    else
      false -> {:error, :not_found}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  def fetch_round_games(id, opts \\ []) do
    if valid_id?(id) do
      fetch_round(
        Keyword.get(opts, :http_client, ReqHttpClient),
        %{tour: %{"slug" => "-"}, round: %{"id" => id, "slug" => "-"}}
      )
    else
      {:error, :not_found}
    end
  end

  defp valid_id?(id), do: is_binary(id) and Regex.match?(~r/^[a-zA-Z0-9]{8}$/, id)

  defp fetch_round(http, %{tour: tour, round: round}) do
    json_path = "/api/broadcast/#{tour["slug"]}/#{round["slug"]}/#{round["id"]}"
    pgn_path = "/api/broadcast/round/#{round["id"]}.pgn?clocks=true&comments=true"

    with {:ok, json_body} <- get(http, json_path, "application/json"),
         sampled_at_ms = System.system_time(:millisecond),
         {:ok, round_data} <- Jason.decode(json_body),
         true <- valid_round?(round_data),
         {:ok, pgn} <- get(http, pgn_path, "application/x-chess-pgn"),
         {:ok, parsed_games} <- PgnParser.parse(pgn) do
      {:ok, normalize_round(round_data, parsed_games, tour, sampled_at_ms)}
    else
      false -> {:error, :invalid_response}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_round(
         %{"tour" => tour, "round" => round, "games" => games},
         parsed_games,
         source_tour,
         sampled_at_ms
       ) do
    parsed_by_id =
      Map.new(parsed_games, fn parsed ->
        {parsed |> get_in(["headers", "GameURL"]) |> game_id_from_url(), parsed}
      end)

    games
    |> Enum.flat_map(fn game ->
      with id when is_binary(id) <- game["id"],
           %{} = parsed <- parsed_by_id[id],
           [white, black | _] <- game["players"] do
        moves = parsed["moves"] || []

        [
          normalize_game(
            id,
            tour,
            round,
            game,
            white,
            black,
            parsed,
            moves,
            source_tour,
            sampled_at_ms
          )
        ]
      else
        _ -> []
      end
    end)
  end

  defp normalize_game(
         id,
         tour,
         round,
         game,
         white,
         black,
         parsed,
         moves,
         source_tour,
         sampled_at_ms
       ) do
    headers = parsed["headers"] || %{}
    last_move = List.last(moves)

    %{
      game_id: id,
      tournament_id:
        tour["id"] || source_tour["id"] || source_tour["slug"] || slugify(tour["name"]),
      round_id: round["id"],
      result: game["status"] || headers["Result"] || "*",
      initial_fen: headers["FEN"],
      tournament: tour["name"],
      tournament_image: source_tour["image"] || tour["image"],
      round: round["name"],
      white: player(white, headers, "White"),
      black: player(black, headers, "Black"),
      fen: parsed["fen"] || game["fen"],
      last_move: last_move,
      moves: moves,
      live_clock: live_clock(game, white, black, parsed, sampled_at_ms),
      lichess_url: headers["GameURL"] || "#{round["url"]}/#{id}"
    }
  end

  # Lichess clocks are centiseconds; thinkTime is seconds since the last move.
  # JSON and PGN are separate requests: never attach an old turn's clock to a newer board.
  defp live_clock(game, white, black, parsed, sampled_at_ms) do
    if game["fen"] == parsed["fen"] do
      %{
        white_ms: nonnegative_scaled(white["clock"], 10),
        black_ms: nonnegative_scaled(black["clock"], 10),
        think_time_ms: nonnegative_scaled(game["thinkTime"], 1_000),
        sampled_at_ms: sampled_at_ms
      }
    end
  end

  defp nonnegative_scaled(value, scale) when is_number(value) and value >= 0,
    do: round(value * scale)

  defp nonnegative_scaled(_, _), do: nil

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

  defp valid_round?(%{"tour" => %{}, "round" => %{}, "games" => games}) when is_list(games),
    do: true

  defp valid_round?(_), do: false

  defp game_id_from_url(url) when is_binary(url),
    do: url |> String.trim_trailing("/") |> String.split("/") |> List.last()

  defp game_id_from_url(_), do: nil

  defp get(http, path, accept) do
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
