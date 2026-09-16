defmodule ChessDuelBackend.Broadcasts.HttpClient do
  @callback get(String.t(), keyword()) ::
              {:ok, %{status: integer(), body: binary()}} | {:error, term()}
end

defmodule ChessDuelBackend.Broadcasts.ReqHttpClient do
  @behaviour ChessDuelBackend.Broadcasts.HttpClient
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_),
    do:
      {:ok,
       %{
         next_request: System.monotonic_time(:millisecond),
         cooldown: System.monotonic_time(:millisecond)
       }}

  @impl true
  def handle_call({:get, url, options}, _from, state) do
    now = System.monotonic_time(:millisecond)

    if state.cooldown > now do
      {:reply, {:ok, %{status: 429, body: ""}}, state}
    else
      # Uma requisição por vez, com intervalo compartilhado entre feed e histórico.
      Process.sleep(max(state.next_request - now, 0))
      result = request(url, options)
      now = System.monotonic_time(:millisecond)

      cooldown =
        case result do
          {:ok, %{status: 429}} -> now + 60_000
          _ -> state.cooldown
        end

      {:reply, result, %{state | next_request: now + 1_000, cooldown: cooldown}}
    end
  end

  @impl true
  def get(url, options), do: GenServer.call(__MODULE__, {:get, url, options}, 60_000)

  defp request(url, options) do
    headers = Keyword.fetch!(options, :headers)
    timeout = Keyword.get(options, :timeout, 5_000)

    case Req.get(url,
           headers: headers,
           receive_timeout: timeout,
           connect_options: [timeout: timeout],
           retry: false,
           decode_body: false
         ) do
      {:ok, %Req.Response{status: status, body: body}} when is_binary(body) ->
        {:ok, %{status: status, body: body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: IO.iodata_to_binary(body)}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
