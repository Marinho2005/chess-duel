defmodule ChessDuelBackend.Broadcasts.HttpClient do
  @callback get(String.t(), keyword()) ::
              {:ok, %{status: integer(), body: binary()}} | {:error, term()}
end

defmodule ChessDuelBackend.Broadcasts.ReqHttpClient do
  @behaviour ChessDuelBackend.Broadcasts.HttpClient

  @impl true
  def get(url, options) do
    headers = Keyword.fetch!(options, :headers)
    timeout = Keyword.get(options, :timeout, 5_000)

    case Req.get(url, headers: headers, receive_timeout: timeout, retry: false, decode_body: false) do
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
