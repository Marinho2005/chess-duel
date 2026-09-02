defmodule ChessDuelBackendWeb.PuzzleController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Puzzles

  def next(conn, _params) do
    user = conn.assigns.current_user

    case Puzzles.next_puzzle(user.id, user.puzzle_rating) do
      {:ok, puzzle, expected_index} ->
        json(conn, %{
          puzzle: Puzzles.public_puzzle(puzzle, expected_index),
          puzzle_rating: user.puzzle_rating
        })

      {:error, :no_puzzles} ->
        conn |> put_status(:not_found) |> json(%{error: "no_puzzles_available"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def summary(conn, _params), do: json(conn, Puzzles.mode_summary(conn.assigns.current_user.id))

  def attempt(conn, %{"id" => puzzle_id} = params) do
    with {:ok, index} <- parse_index(params["index"]),
         {:ok, move} <- Puzzles.uci_move(params["from"], params["to"], params["promotion"]),
         {:ok, result} <-
           Puzzles.submit_attempt(conn.assigns.current_user.id, puzzle_id, index, move) do
      json(conn, result)
    else
      {:error, :invalid_index} ->
        bad_request(conn, "invalid_index")

      {:error, :invalid_move} ->
        bad_request(conn, "invalid_move")

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "puzzle_not_found"})

      {:error, :already_completed} ->
        conn |> put_status(:conflict) |> json(%{error: "already_completed"})

      {:error, {:unexpected_index, expected}} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "unexpected_index", expected_index: expected})
    end
  end

  defp parse_index(value) when is_integer(value) and value >= 1, do: {:ok, value}
  defp parse_index(_), do: {:error, :invalid_index}

  defp bad_request(conn, error), do: conn |> put_status(:bad_request) |> json(%{error: error})
end
