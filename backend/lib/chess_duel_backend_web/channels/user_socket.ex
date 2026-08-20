defmodule ChessDuelBackendWeb.UserSocket do
  use Phoenix.Socket

  channel "games:*", ChessDuelBackendWeb.GamesChannel
  channel "game:*", ChessDuelBackendWeb.GameChannel

  @impl true
  def connect(params, socket, _connect_info) do
    player_id = Map.get(params, "player_id", "anonymous")
    {:ok, assign(socket, :player_id, player_id)}
  end

  @impl true
  def id(_socket), do: nil
end
