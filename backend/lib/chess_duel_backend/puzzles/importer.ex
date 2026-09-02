defmodule ChessDuelBackend.Puzzles.Importer do
  @moduledoc "Importador streaming do CSV público de puzzles do Lichess."

  alias ChessDuelBackend.Puzzles.Puzzle
  alias ChessDuelBackend.Repo

  @required_headers ~w(PuzzleId FEN Moves Rating Popularity Themes)
  @batch_size 1_000

  def import(path, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50_000)
    minimum_popularity = Keyword.get(opts, :minimum_popularity, 80)
    quota = ceil(limit / 5)

    # Popularidade >= 80 elimina itens mal avaliados. As cotas iguais nestas
    # cinco faixas evitam que o subconjunto seja dominado pelo rating mediano.
    initial = %{imported: 0, skipped: 0, rows: [], buckets: %{}, quota: quota, limit: limit}

    path
    |> File.stream!([], :line)
    |> Stream.transform(nil, fn line, headers ->
      fields = parse_csv_line(String.trim_trailing(line))

      if headers do
        {[{fields, headers}], headers}
      else
        normalized = List.update_at(fields, 0, &String.trim_leading(&1, <<0xEF, 0xBB, 0xBF>>))
        validate_headers!(normalized)
        {[], header_indexes(normalized)}
      end
    end)
    |> Enum.reduce_while(initial, fn {fields, indexes}, state ->
      row = row_from_fields(fields, indexes, state, minimum_popularity)
      state = if row, do: add_row(state, row), else: %{state | skipped: state.skipped + 1}
      state = maybe_flush(state)

      if state.imported >= state.limit, do: {:halt, state}, else: {:cont, state}
    end)
    |> flush()
    |> then(fn state -> {:ok, %{imported: state.imported, skipped: state.skipped}} end)
  end

  def parse_csv_line(line) when is_binary(line), do: parse_chars(line, false, "", [])

  defp parse_chars(<<>>, _quoted, field, fields), do: Enum.reverse([field | fields])

  defp parse_chars(<<"\"\"", rest::binary>>, true, field, fields),
    do: parse_chars(rest, true, field <> "\"", fields)

  defp parse_chars(<<"\"", rest::binary>>, quoted, field, fields),
    do: parse_chars(rest, not quoted, field, fields)

  defp parse_chars(<<",", rest::binary>>, false, field, fields),
    do: parse_chars(rest, false, "", [field | fields])

  defp parse_chars(<<char::utf8, rest::binary>>, quoted, field, fields),
    do: parse_chars(rest, quoted, field <> <<char::utf8>>, fields)

  defp header_indexes(headers) do
    headers |> Enum.with_index() |> Map.new()
  end

  defp validate_headers!(headers) do
    missing = @required_headers -- headers

    if missing != [],
      do: raise(ArgumentError, "CSV sem colunas obrigatórias: #{Enum.join(missing, ", ")}")
  end

  defp row_from_fields(fields, indexes, state, minimum_popularity) do
    # A ordem oficial é estável; os índices são descobertos pelo cabeçalho para
    # continuar aceitando amostras que incluam ou omitam colunas opcionais.
    with {rating, ""} <- Integer.parse(at(fields, indexes, "Rating")),
         {popularity, ""} <- Integer.parse(at(fields, indexes, "Popularity")),
         true <- popularity >= minimum_popularity,
         bucket <- rating_bucket(rating),
         true <- Map.get(state.buckets, bucket, 0) < state.quota,
         moves when length(moves) >= 2 and rem(length(moves), 2) == 0 <-
           String.split(at(fields, indexes, "Moves"), " ", trim: true) do
      now = DateTime.utc_now(:second)

      %{
        id: Ecto.UUID.generate(),
        lichess_id: at(fields, indexes, "PuzzleId"),
        fen: at(fields, indexes, "FEN"),
        moves: moves,
        rating: rating,
        themes: String.split(at(fields, indexes, "Themes"), " ", trim: true),
        popularity: popularity,
        inserted_at: now,
        updated_at: now,
        bucket: bucket
      }
    else
      _ -> nil
    end
  end

  defp add_row(state, row) do
    bucket = row.bucket
    row = Map.delete(row, :bucket)

    %{
      state
      | rows: [row | state.rows],
        imported: state.imported + 1,
        buckets: Map.update(state.buckets, bucket, 1, &(&1 + 1))
    }
  end

  defp maybe_flush(%{rows: rows} = state) when length(rows) >= @batch_size, do: flush(state)
  defp maybe_flush(state), do: state

  defp flush(%{rows: []} = state), do: state

  defp flush(state) do
    Repo.insert_all(Puzzle, state.rows,
      on_conflict: {:replace, [:fen, :moves, :rating, :themes, :popularity, :updated_at]},
      conflict_target: :lichess_id
    )

    %{state | rows: []}
  end

  defp at(fields, indexes, name), do: Enum.at(fields, Map.fetch!(indexes, name), "")

  defp rating_bucket(rating) when rating < 1_000, do: :under_1000
  defp rating_bucket(rating) when rating < 1_400, do: :from_1000
  defp rating_bucket(rating) when rating < 1_800, do: :from_1400
  defp rating_bucket(rating) when rating < 2_200, do: :from_1800
  defp rating_bucket(_rating), do: :over_2200
end
