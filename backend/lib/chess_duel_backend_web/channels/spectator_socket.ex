defmodule ChessDuelBackendWeb.SpectatorSocket do
  use Phoenix.Socket

  # Public transport deliberately has no gameplay or matchmaking channels.
  channel "watch_game:*", ChessDuelBackendWeb.GameWatchChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
