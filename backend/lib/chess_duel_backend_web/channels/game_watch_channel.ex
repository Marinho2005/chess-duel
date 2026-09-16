defmodule ChessDuelBackendWeb.GameWatchChannel do
  use ChessDuelBackendWeb, :channel

  alias ChessDuelBackend.{GameRegistry, Repo}
  alias ChessDuelBackend.Games.Game
  alias ChessDuelBackendWeb.{Endpoint, GameChannel}

  @impl true
  def join("watch_game:" <> game_id, _payload, socket) when byte_size(game_id) <= 128 do
    # Subscribe before the snapshot so moves concurrent with joining are not lost.
    Endpoint.subscribe("game:" <> game_id)

    case read_state(game_id) do
      {:ok, state} ->
        socket = socket |> assign(:game_id, game_id) |> assign(:players, GameChannel.spectator_players(state))
        {:ok, payload(state, socket), schedule(socket, state)}

      :error ->
        game = Repo.get_by(Game, game_id: game_id)
        {:error, %{reason: "game_not_live", review_game_id: if(game && game.status == "finished", do: game.id)}}
    end
  end

  def join(_, _, _), do: {:error, %{reason: "invalid_game"}}

  @impl true
  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{reason: "read_only"}}, socket}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: event}, socket)
      when event in ["move_made", "game_over", "game_started", "clock_sync"] do
    refresh(socket)
  end

  def handle_info(:refresh, socket), do: refresh(socket)
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def terminate(_, socket) do
    cancel_timer(socket)
    :ok
  end

  defp refresh(socket) do
    cancel_timer(socket)

    case read_state(socket.assigns.game_id) do
      {:ok, state} ->
        push(socket, "state", payload(state, socket))
        {:noreply, schedule(socket, state)}

      :error ->
        push(socket, "unavailable", %{})
        {:stop, :normal, socket}
    end
  end

  defp schedule(socket, %{status: "finished"}), do: assign(socket, :timer, nil)
  defp schedule(socket, _), do: assign(socket, :timer, Process.send_after(self(), :refresh, 1_000))
  defp cancel_timer(socket) do
    if socket.assigns[:timer], do: Process.cancel_timer(socket.assigns.timer)
  end

  defp read_state(game_id) do
    # Never use start_or_get: a spectator must not create or revive a game.
    case Registry.lookup(GameRegistry, game_id) do
      [{pid, _}] -> GenServer.call(pid, :get_state, 1_000)
      [] -> :error
    end
  catch
    :exit, _ -> :error
  end

  defp payload(state, socket) do
    state
    |> Map.take([:fen, :moves, :current_turn, :status, :game_over_reason,
      :white_time_remaining_ms, :black_time_remaining_ms])
    |> Map.merge(socket.assigns.players)
    |> Map.put(:review_game_id, state.database_id)
    |> Map.put(:guest_game, state.game_type == :guest)
  end
end
