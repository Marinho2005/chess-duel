defmodule ChessDuelBackend.Games.Matchmaker do
  @moduledoc "Fila de matchmaking por rating persistida em sorted sets do Valkey."

  use GenServer

  alias ChessDuelBackend.Games.{GameServer, TimeControl}
  alias ChessDuelBackend.Accounts.User

  require Logger

  @check_interval_ms 1_000
  @base_tolerance 100
  @tolerance_step 50
  @tolerance_step_interval_ms 15_000
  @maximum_tolerance 800
  @waiting_warning_ms 120_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def join_queue(user, time_control_id),
    do: GenServer.call(__MODULE__, {:join_queue, user, time_control_id})

  def leave_queue(user_id), do: GenServer.call(__MODULE__, {:leave_queue, user_id})
  def match_now, do: GenServer.call(__MODULE__, :match_now)

  def queue_entries(time_control_id),
    do: GenServer.call(__MODULE__, {:queue_entries, time_control_id})

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :check_interval_ms, @check_interval_ms)
    schedule_match(interval)
    {:ok, %{check_interval_ms: interval}}
  end

  @impl true
  def handle_call({:join_queue, user, time_control_id}, _from, state) do
    with {:ok, control} <- TimeControl.fetch(time_control_id),
         :ok <- remove_user_from_all_queues(user.id),
         {:ok, member} <- encode_member(user, control),
         rating = User.rating_for(user, TimeControl.rating_category(control)),
         {:ok, _result} <-
           Redix.command(:valkey, ["ZADD", queue_key(control.id), rating, member]) do
      {:reply, {:ok, %{time_control: control, joined_at: Jason.decode!(member)["joined_at"]}},
       state}
    else
      {:error, :invalid_time_control} -> {:reply, {:error, :invalid_time_control}, state}
      {:error, reason} -> {:reply, {:error, {:valkey_error, reason}}, state}
    end
  end

  def handle_call({:leave_queue, user_id}, _from, state) do
    reply = remove_user_from_all_queues(user_id)
    {:reply, reply, state}
  end

  def handle_call({:queue_entries, time_control_id}, _from, state) do
    reply =
      with {:ok, control} <- TimeControl.fetch(time_control_id) do
        read_queue(control)
      end

    {:reply, reply, state}
  end

  def handle_call(:match_now, _from, state) do
    {:reply, match_all_queues(), state}
  end

  @impl true
  def handle_info(:match_queues, state) do
    match_all_queues()
    schedule_match(state.check_interval_ms)
    {:noreply, state}
  end

  defp match_all_queues do
    Enum.each(TimeControl.all(), &match_queue/1)
    :ok
  rescue
    exception ->
      Logger.error("Falha ao processar matchmaking: #{Exception.message(exception)}")
      {:error, exception}
  end

  defp match_queue(control) do
    case read_queue(control) do
      {:ok, entries} ->
        now = System.system_time(:millisecond)
        notify_long_waits(entries, control, now)

        entries
        |> build_pairs(now)
        |> Enum.each(&create_match(&1, control))

      {:error, reason} ->
        Logger.error("Falha ao ler fila #{control.id}: #{inspect(reason)}")
    end
  end

  defp build_pairs(entries, now), do: build_pairs(entries, now, [])
  defp build_pairs([], _now, pairs), do: Enum.reverse(pairs)
  defp build_pairs([_single], _now, pairs), do: Enum.reverse(pairs)

  defp build_pairs([player | remaining], now, pairs) do
    {before, candidate_and_after} =
      Enum.split_while(remaining, fn candidate ->
        not compatible?(player, candidate, now)
      end)

    case candidate_and_after do
      [candidate | after_candidate] ->
        build_pairs(before ++ after_candidate, now, [{player, candidate} | pairs])

      [] ->
        build_pairs(remaining, now, pairs)
    end
  end

  defp compatible?(first, second, now) do
    rating_distance = abs(first.rating - second.rating)
    rating_distance <= max(tolerance(first, now), tolerance(second, now))
  end

  # A margem comeca em 100 e cresce 50 pontos a cada 15 segundos, ate 800.
  # Isso favorece partidas equilibradas sem deixar jogadores esperando indefinidamente.
  defp tolerance(player, now) do
    waited_ms = max(now - player.joined_at, 0)
    expansion = div(waited_ms, @tolerance_step_interval_ms) * @tolerance_step
    min(@base_tolerance + expansion, @maximum_tolerance)
  end

  defp create_match({first, second}, control) do
    key = queue_key(control.id)

    case Redix.command(:valkey, ["ZREM", key, first.member, second.member]) do
      {:ok, 2} ->
        {white, black} = randomize_colors(first, second)
        game_id = Ecto.UUID.generate()

        case GameServer.reserve_players(game_id, white.user_id, black.user_id, control) do
          {:ok, _state} ->
            payload = %{game_id: game_id, time_control: control}
            broadcast_match(first.user_id, payload)
            broadcast_match(second.user_id, payload)
            clear_warning(first.user_id)
            clear_warning(second.user_id)

          {:error, reason} ->
            requeue(first, control)
            requeue(second, control)
            Logger.error("Falha ao criar partida de matchmaking: #{inspect(reason)}")
        end

      {:ok, _removed_count} ->
        :ok

      {:error, reason} ->
        Logger.error("Falha ao remover par da fila #{control.id}: #{inspect(reason)}")
    end
  end

  defp read_queue(control) do
    with {:ok, members} <- Redix.command(:valkey, ["ZRANGE", queue_key(control.id), "0", "-1"]) do
      entries =
        members
        |> Enum.flat_map(fn member ->
          case Jason.decode(member) do
            {:ok, data} ->
              [
                %{
                  user_id: data["user_id"],
                  rating: data["rating"],
                  joined_at: data["joined_at"],
                  member: member
                }
              ]

            {:error, _reason} ->
              Redix.command(:valkey, ["ZREM", queue_key(control.id), member])
              []
          end
        end)

      {:ok, entries}
    end
  end

  defp remove_user_from_all_queues(user_id) do
    Enum.reduce_while(TimeControl.all(), :ok, fn control, :ok ->
      with {:ok, entries} <- read_queue(control),
           members = for(entry <- entries, entry.user_id == user_id, do: entry.member),
           :ok <- remove_members(queue_key(control.id), members) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> tap(fn _result -> clear_warning(user_id) end)
  end

  defp remove_members(_key, []), do: :ok

  defp remove_members(key, members) do
    case Redix.command(:valkey, ["ZREM", key | members]) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_member(user, control) do
    Jason.encode(%{
      user_id: user.id,
      rating: User.rating_for(user, TimeControl.rating_category(control)),
      joined_at: System.system_time(:millisecond)
    })
  end

  defp requeue(player, control) do
    Redix.command(:valkey, ["ZADD", queue_key(control.id), player.rating, player.member])
  end

  defp notify_long_waits(entries, control, now) do
    entries
    |> Enum.filter(&(now - &1.joined_at >= @waiting_warning_ms))
    |> Enum.each(fn player ->
      case Redix.command(:valkey, [
             "SET",
             warning_key(player.user_id),
             "1",
             "NX",
             "EX",
             "300"
           ]) do
        {:ok, "OK"} ->
          ChessDuelBackendWeb.Endpoint.broadcast(
            user_topic(player.user_id),
            "queue_waiting",
            %{time_control: control, message: "A busca esta demorando; ampliamos o rating."}
          )

        _ ->
          :ok
      end
    end)
  end

  defp randomize_colors(first, second) do
    if :rand.uniform(2) == 1, do: {first, second}, else: {second, first}
  end

  defp broadcast_match(user_id, payload) do
    ChessDuelBackendWeb.Endpoint.broadcast(user_topic(user_id), "match_found", payload)
  end

  defp clear_warning(user_id), do: Redix.command(:valkey, ["DEL", warning_key(user_id)])
  defp queue_key(control_id), do: "matchmaking:queue:#{control_id}"
  defp warning_key(user_id), do: "matchmaking:warning:#{user_id}"
  defp user_topic(user_id), do: "matchmaking:#{user_id}"

  defp schedule_match(interval), do: Process.send_after(self(), :match_queues, interval)
end
