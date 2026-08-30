defmodule ChessDuelBackend.GameAnalysis.Stockfish do
  @moduledoc "Cliente UCI mínimo. Um único processo Stockfish é reutilizado durante cada job."

  @timeout 30_000

  def analyze(moves, opts \\ []) do
    config = Application.get_env(:chess_duel_backend, :stockfish, [])
    executable = Keyword.get(opts, :path) || Keyword.get(config, :path) || find_executable()
    depth = Keyword.get(opts, :depth, Keyword.get(config, :depth, 12))

    with {:ok, engine} <- open(executable),
         :ok <- initialize(engine, config),
         {:ok, positions} <- analyze_positions(engine, moves, depth) do
      Port.command(engine, "quit\n")
      {:ok, format_results(moves, positions, depth)}
    end
  end

  def classify(_loss, played, best) when played == best, do: "best"
  def classify(loss, _played, _best) when loss <= 10, do: "best"
  def classify(loss, _played, _best) when loss <= 50, do: "good"
  def classify(loss, _played, _best) when loss <= 100, do: "inaccuracy"
  def classify(loss, _played, _best) when loss <= 250, do: "mistake"
  def classify(_loss, _played, _best), do: "blunder"

  def parse_score(line) do
    case Regex.run(~r/\bscore (cp|mate) (-?\d+)\b/, line) do
      [_, type, value] -> %{"type" => type, "value" => String.to_integer(value)}
      _ -> nil
    end
  end

  defp open(nil), do: {:error, "Stockfish não encontrado; configure STOCKFISH_PATH"}

  defp open(path) do
    {:ok, Port.open({:spawn_executable, path}, [:binary, :exit_status, {:line, 65_536}, args: []])}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp initialize(engine, config) do
    Port.command(engine, "uci\n")

    with :ok <- await_token(engine, "uciok") do
      Port.command(engine, "setoption name Threads value #{Keyword.get(config, :threads, 1)}\n")
      Port.command(engine, "setoption name Hash value #{Keyword.get(config, :hash_mb, 32)}\n")
      Port.command(engine, "isready\n")
      await_token(engine, "readyok")
    end
  end

  defp analyze_positions(engine, moves, depth) do
    Enum.reduce_while(0..length(moves), {:ok, []}, fn ply, {:ok, acc} ->
      played = Enum.take(moves, ply) |> Enum.map_join(" ", &uci_move/1)

      command =
        if played == "", do: "position startpos\n", else: "position startpos moves #{played}\n"

      Port.command(engine, command)
      Port.command(engine, "go depth #{depth}\n")

      case await_bestmove(engine, nil) do
        {:ok, result} -> {:cont, {:ok, [normalize(result, ply) | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, positions} -> {:ok, Enum.reverse(positions)}
      error -> error
    end
  end

  defp await_bestmove(engine, latest) do
    receive do
      {^engine, {:data, {:eol, line}}} ->
        text = to_string(line)

        cond do
          String.starts_with?(text, "bestmove ") ->
            [_, best | _] = String.split(text)
            {:ok, Map.merge(latest || %{}, %{best_move: best})}

          String.starts_with?(text, "info ") ->
            score = parse_score(text)

            pv =
              case Regex.run(~r/\bpv (.+)$/, text) do
                [_, value] -> String.split(value)
                _ -> nil
              end

            next = if score, do: %{score: score, pv: pv || []}, else: latest
            await_bestmove(engine, next)

          true ->
            await_bestmove(engine, latest)
        end

      {^engine, {:exit_status, status}} ->
        {:error, "Stockfish encerrou com status #{status}"}
    after
      @timeout -> {:error, "Stockfish excedeu o tempo limite"}
    end
  end

  defp await_token(engine, token) do
    receive do
      {^engine, {:data, {:eol, line}}} ->
        if String.contains?(to_string(line), token), do: :ok, else: await_token(engine, token)

      {^engine, {:exit_status, status}} ->
        {:error, "Stockfish encerrou com status #{status}"}
    after
      @timeout -> {:error, "Stockfish não respondeu a #{token}"}
    end
  end

  defp normalize(%{score: score} = result, ply) do
    value = if rem(ply, 2) == 0, do: score["value"], else: -score["value"]
    %{result | score: %{score | "value" => value}}
  end

  defp format_results(moves, positions, depth) do
    analyzed =
      moves
      |> Enum.with_index()
      |> Enum.map(fn {move, index} ->
        before = Enum.at(positions, index)
        after_move = Enum.at(positions, index + 1)
        color = if rem(index, 2) == 0, do: "white", else: "black"
        loss = centipawn_loss(before.score, after_move.score, color)

        %{
          "ply" => index + 1,
          "move_number" => div(index, 2) + 1,
          "color" => color,
          "played_move" => uci_move(move),
          "best_move" => before.best_move,
          "evaluation_before" => before.score,
          "evaluation" => after_move.score,
          "principal_variation" => before.pv,
          "centipawn_loss" => loss,
          "classification" => classify(loss, uci_move(move), before.best_move)
        }
      end)

    %{"depth" => depth, "initial_evaluation" => hd(positions).score, "moves" => analyzed}
  end

  defp centipawn_loss(before, after_move, color) do
    before_value = comparable_score(before)
    after_value = comparable_score(after_move)
    raw = if color == "white", do: before_value - after_value, else: after_value - before_value
    max(0, raw)
  end

  defp comparable_score(%{"type" => "cp", "value" => value}), do: value
  defp comparable_score(%{"type" => "mate", "value" => value}) when value > 0, do: 100_000 - value
  defp comparable_score(%{"type" => "mate", "value" => value}), do: -100_000 - value

  defp uci_move(move) do
    from = move["from"] || move[:from]
    to = move["to"] || move[:to]
    promotion = move["promotion"] || move[:promotion] || ""
    "#{from}#{to}#{promotion}"
  end

  defp find_executable do
    System.find_executable("stockfish") ||
      if(File.exists?("/usr/games/stockfish"), do: "/usr/games/stockfish")
  end
end
