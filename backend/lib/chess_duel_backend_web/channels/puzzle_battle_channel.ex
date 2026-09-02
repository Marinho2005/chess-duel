defmodule ChessDuelBackendWeb.PuzzleBattleChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.Puzzles
  alias ChessDuelBackend.Puzzles.BattleServer

  @impl true
  def join("puzzle_battle:" <> battle_id, _payload, socket) do
    if socket.assigns[:identity_type] != :user do
      {:error, %{reason: "registered_users_only"}}
    else
      case BattleServer.snapshot(battle_id, socket.assigns.user_id) do
        {:ok, payload} -> {:ok, payload, assign(socket, :battle_id, battle_id)}
        {:error, reason} -> {:error, %{reason: Atom.to_string(reason)}}
      end
    end
  end

  @impl true
  def handle_in("attempt", payload, socket) do
    with {:ok, index} <- parse_index(payload["index"]),
         {:ok, move} <- Puzzles.uci_move(payload["from"], payload["to"], payload["promotion"]),
         {:ok, result} <-
           BattleServer.attempt(socket.assigns.battle_id, socket.assigns.user_id, index, move) do
      {:reply, {:ok, result}, socket}
    else
      {:error, {:unexpected_index, expected}} ->
        {:reply, {:error, %{reason: "unexpected_index", expected_index: expected}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
    end
  end

  defp parse_index(value) when is_integer(value) and value >= 1, do: {:ok, value}
  defp parse_index(_), do: {:error, :invalid_index}
end
