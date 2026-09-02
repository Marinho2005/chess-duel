defmodule ChessDuelBackendWeb.PuzzleRushController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Puzzles
  alias ChessDuelBackend.Puzzles.RushServer

  def start(conn, params) do
    with {:ok, duration} <- duration(params["duration_seconds"]),
         {:ok, payload} <- RushServer.start(conn.assigns.current_user.id, duration) do
      conn |> put_status(:created) |> json(payload)
    else
      {:error, :invalid_duration} ->
        bad_request(conn, "invalid_duration")

      {:error, :no_puzzles} ->
        conn |> put_status(:not_found) |> json(%{error: "no_puzzles_available"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def show(conn, %{"session_id" => session_id}) do
    case RushServer.snapshot(session_id, conn.assigns.current_user.id) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, :session_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session_not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def attempt(conn, %{"session_id" => session_id} = params) do
    with {:ok, index} <- parse_index(params["index"]),
         {:ok, move} <- Puzzles.uci_move(params["from"], params["to"], params["promotion"]),
         {:ok, payload} <- RushServer.attempt(session_id, conn.assigns.current_user.id, index, move) do
      json(conn, payload)
    else
      {:error, :invalid_index} ->
        bad_request(conn, "invalid_index")

      {:error, :invalid_move} ->
        bad_request(conn, "invalid_move")

      {:error, :session_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session_not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, {:unexpected_index, expected}} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "unexpected_index", expected_index: expected})
    end
  end

  defp duration(nil), do: {:ok, 180}
  defp duration(value) when value in [180, 300], do: {:ok, value}
  defp duration(_), do: {:error, :invalid_duration}

  defp parse_index(value) when is_integer(value) and value >= 1, do: {:ok, value}
  defp parse_index(_), do: {:error, :invalid_index}

  defp bad_request(conn, error), do: conn |> put_status(:bad_request) |> json(%{error: error})
end
