defmodule ChessDuelBackendWeb.Plugs.RuntimeCors do
  @moduledoc "Le origens por requisicao, nunca ao compilar o Endpoint."
  @behaviour Plug
  def init(options), do: options

  def call(conn, _options) do
    options = Application.fetch_env!(:chess_duel_backend, :cors) |> CORSPlug.init()
    CORSPlug.call(conn, options)
  end
end
