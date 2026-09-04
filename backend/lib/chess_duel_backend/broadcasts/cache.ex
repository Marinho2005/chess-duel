defmodule ChessDuelBackend.Broadcasts.Cache do
  use GenServer

  require Logger

  @default_interval 20_000
  @rate_limit_interval 60_000
  @max_games_per_tournament 30

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  def list_games(server \\ __MODULE__), do: GenServer.call(server, :list_games)
  def list_tournaments(server \\ __MODULE__), do: GenServer.call(server, :list_tournaments)

  def list_tournament_games(tournament_id, server \\ __MODULE__),
    do: GenServer.call(server, {:list_tournament_games, tournament_id})

  def get_game(game_id, server \\ __MODULE__), do: GenServer.call(server, {:get_game, game_id})
  def refresh(server \\ __MODULE__), do: GenServer.call(server, :refresh, 30_000)

  @impl true
  def init(opts) do
    config = Application.get_env(:chess_duel_backend, :lichess_broadcasts, [])

    state = %{
      games: %{},
      client:
        Keyword.get(
          opts,
          :client,
          Keyword.get(config, :client, ChessDuelBackend.Broadcasts.LichessClient)
        ),
      interval:
        Keyword.get(opts, :interval_ms, Keyword.get(config, :poll_interval_ms, @default_interval)),
      auto_refresh: Keyword.get(opts, :auto_refresh, Keyword.get(config, :auto_refresh, true))
    }

    if state.auto_refresh, do: send(self(), :refresh)
    {:ok, state}
  end

  @impl true
  def handle_call(:list_games, _from, state),
    do: {:reply, state.games |> Map.values() |> Enum.sort_by(& &1.game_id), state}

  def handle_call(:list_tournaments, _from, state) do
    tournaments =
      state.games
      |> Map.values()
      |> Enum.group_by(& &1.tournament_id)
      |> Enum.map(fn {id, games} ->
        first_game = hd(games)

        %{
          tournament_id: id,
          name: Map.fetch!(first_game, :tournament),
          image_url: Map.get(first_game, :tournament_image),
          live_games: length(games)
        }
      end)
      |> Enum.sort_by(&String.downcase(&1.name))

    {:reply, tournaments, state}
  end

  def handle_call({:list_tournament_games, tournament_id}, _from, state) do
    games =
      state.games
      |> Map.values()
      |> Enum.filter(&(&1.tournament_id == tournament_id))
      |> Enum.sort_by(& &1.game_id)

    {:reply, games, state}
  end

  def handle_call({:get_game, id}, _from, state), do: {:reply, Map.fetch(state.games, id), state}

  def handle_call(:refresh, _from, state) do
    {reply, next_state, _delay} = update(state)
    {:reply, reply, next_state}
  end

  @impl true
  def handle_info(:refresh, state) do
    {_reply, next_state, delay} = update(state)
    Process.send_after(self(), :refresh, delay)
    {:noreply, next_state}
  end

  defp update(state) do
    case fetch_games(state.client) do
      {:ok, games} ->
        next =
          games
          |> Enum.group_by(& &1.tournament_id)
          |> Enum.flat_map(fn {_tournament_id, tournament_games} ->
            Enum.take(tournament_games, @max_games_per_tournament)
          end)
          |> Map.new(&{&1.game_id, &1})

        emit_changes(state.games, next)
        emit_removals(state.games, next)
        {:ok, %{state | games: next}, state.interval}

      {:error, reason} ->
        Logger.warning("Lichess broadcast refresh failed: #{inspect(reason)}")

        delay =
          if reason == :rate_limited,
            do: max(state.interval, @rate_limit_interval),
            else: state.interval

        {{:error, reason}, state, delay}
    end
  end

  defp fetch_games(client) when is_function(client, 0), do: client.()
  defp fetch_games(client), do: client.fetch_live_games()

  defp emit_changes(previous, current) do
    Enum.each(current, fn {id, game} ->
      if changed?(previous[id], game) do
        ChessDuelBackendWeb.Endpoint.broadcast("broadcast_watch:#{id}", "broadcast_move", %{
          game_id: id,
          fen: game.fen,
          last_move: game.last_move,
          moves: game.moves
        })
      end
    end)
  end

  defp changed?(nil, _game), do: false

  defp changed?(old, new),
    do: {old.fen, length(old.moves), old.last_move} != {new.fen, length(new.moves), new.last_move}

  defp emit_removals(previous, current) do
    previous
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(current, &1))
    |> Enum.each(fn id ->
      ChessDuelBackendWeb.Endpoint.broadcast(
        "broadcast_watch:#{id}",
        "broadcast_ended",
        %{game_id: id}
      )
    end)
  end
end
