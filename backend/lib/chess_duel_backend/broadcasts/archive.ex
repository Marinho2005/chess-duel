defmodule ChessDuelBackend.Broadcasts.Archive do
  @moduledoc "Cache limitado para rodadas consultadas sob demanda, sem bloquear o feed ao vivo."
  use GenServer
  require Logger
  alias ChessDuelBackend.Broadcasts.LichessClient

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def tournament(id, server \\ __MODULE__),
    do: GenServer.call(server, {:get, {:tournament, id}}, 120_000)

  def round_games(id, server \\ __MODULE__),
    do: GenServer.call(server, {:get, {:round, id}}, 120_000)

  @impl true
  def init(opts),
    do:
      {:ok,
       %{
         entries: %{},
         pending: %{},
         cooldown: System.monotonic_time(:millisecond),
         fetch: Keyword.get(opts, :fetch)
       }}

  @impl true
  def handle_call({:get, key}, from, state) do
    now = System.monotonic_time(:millisecond)

    case state.entries[key] do
      {expires, result} when expires > now ->
        {:reply, result, state}

      _ ->
        existing = Enum.find(state.pending, fn {_ref, item} -> item.key == key end)

        cond do
          existing ->
            {ref, item} = existing
            {:noreply, put_in(state.pending[ref], %{item | callers: [from | item.callers]})}

          state.cooldown > now or map_size(state.pending) >= 4 ->
            {:reply, {:error, :rate_limited}, state}

          true ->
            task =
              Task.Supervisor.async_nolink(ChessDuelBackend.BroadcastFetchSupervisor, fn ->
                # Do not retain a local function capture across Phoenix code reloads.
                if state.fetch, do: state.fetch.(key), else: fetch(key)
              end)

            {:noreply, put_in(state.pending[task.ref], %{key: key, callers: [from]})}
        end
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state),
    do: finish(ref, {:error, :unavailable}, state)

  defp finish(ref, result, state) do
    {item, pending} = Map.pop(state.pending, ref)

    if item do
      if match?({:error, _}, result) do
        Logger.warning("Broadcast lookup #{inspect(item.key)} failed: #{inspect(result)}")
      end

      Enum.each(item.callers, &GenServer.reply(&1, result))
      now = System.monotonic_time(:millisecond)

      ttl =
        case {item.key, result} do
          {{:tournament, _}, {:ok, _}} ->
            300_000

          {{:round, _}, {:ok, [_ | _] = games}} ->
            if Enum.all?(games, &(&1.result != "*")), do: 3_600_000, else: 20_000

          {_, {:ok, _}} ->
            20_000

          _ ->
            5_000
        end

      entries =
        state.entries
        |> Enum.reject(fn {_key, {expires, _}} -> expires <= now end)
        |> Enum.sort_by(fn {_key, {expires, _}} -> expires end, :desc)
        |> Enum.take(63)
        |> Map.new()

      cooldown = if result == {:error, :rate_limited}, do: now + 60_000, else: state.cooldown

      {:noreply,
       %{
         state
         | pending: pending,
           entries: Map.put(entries, item.key, {now + ttl, result}),
           cooldown: cooldown
       }}
    else
      {:noreply, state}
    end
  end

  defp fetch({:tournament, id}), do: LichessClient.fetch_tournament(id)
  defp fetch({:round, id}), do: LichessClient.fetch_round_games(id)
end
