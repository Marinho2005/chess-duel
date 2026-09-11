defmodule ChessDuelBackend.Broadcasts.LichessClient do
  @moduledoc false

  alias ChessDuelBackend.Broadcasts.ReqHttpClient

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

  # Previews need only the current position. PGN export/parsing must not block them.
  defp fetch_round(http, %{tour: tour, round: round}) do
    path = "/api/broadcast/#{tour["slug"]}/#{round["slug"]}/#{round["id"]}"

    with {:ok, body} <- get(http, path, "application/json"),
         {:ok, data} <- Jason.decode(body),
         true <- valid_round?(data) do
      {:ok, normalize_round(data, tour)}
    else
      false -> {:error, :invalid_response}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_round(%{"tour" => tour, "round" => round, "games" => games}, source_tour) do
    Enum.flat_map(games, fn game ->
      with id when is_binary(id) <- game["id"],
           fen when is_binary(fen) and fen != "" <- game["fen"],
           [white, black | _] <- game["players"] do
        [
          %{
            game_id: id,
            tournament_id: tour["id"] || source_tour["id"] || slugify(tour["name"]),
            round_id: round["id"],
            result: game["status"] || "*",
            initial_fen: nil,
            tournament: tour["name"],
            tournament_image: source_tour["image"] || tour["image"],
            round: round["name"],
            white: player(white, %{}, "White"),
            black: player(black, %{}, "Black"),
            fen: fen,
            last_move: last_move(game["lastMove"]),
            moves: [],
            lichess_url:
              "#{round["url"] || "https://lichess.org/broadcast/-/-/#{round["id"]}"}/#{id}"
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp last_move(uci) when is_binary(uci) do
    if Regex.match?(~r/^[a-h][1-8][a-h][1-8][qrbn]?$/, uci) do
      %{
        from: String.slice(uci, 0, 2),
        to: String.slice(uci, 2, 2),
        promotion: if(String.length(uci) == 5, do: String.at(uci, 4), else: nil),
        san: ""
      }
    end
  end

  defp last_move(_), do: nil

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
