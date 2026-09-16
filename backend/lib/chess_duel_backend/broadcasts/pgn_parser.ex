defmodule ChessDuelBackend.Broadcasts.PgnParser do
  @moduledoc false

  # PGNs grandes não devem ocupar o Port que valida lances das partidas internas.
  def parse(pgn) do
    case System.find_executable("node") do
      nil ->
        {:error, :parser_unavailable}

      node ->
        script = Application.app_dir(:chess_duel_backend, "priv/chess_validator/validator.js")

        port =
          Port.open({:spawn_executable, node}, [
            :binary,
            :exit_status,
            {:line, 1_000_000},
            args: [script]
          ])

        try do
          Port.command(port, Jason.encode!(%{action: "parse_pgn", pgn: pgn}) <> "\n")
          read(port, [], 0, System.monotonic_time(:millisecond) + 10_000)
        after
          if Port.info(port), do: Port.close(port)
        end
    end
  end

  defp read(_port, _parts, size, _deadline) when size > 20_000_000, do: {:error, :pgn_too_large}

  defp read(port, parts, size, deadline) do
    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        read(port, [chunk | parts], size + byte_size(chunk), deadline)

      {^port, {:data, {:eol, chunk}}} ->
        case Jason.decode(IO.iodata_to_binary(Enum.reverse([chunk | parts]))) do
          {:ok, %{"ok" => true, "games" => games}} -> {:ok, games}
          _ -> {:error, :invalid_pgn}
        end

      {^port, {:exit_status, _}} ->
        {:error, :parser_unavailable}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :parser_timeout}
    end
  end
end
