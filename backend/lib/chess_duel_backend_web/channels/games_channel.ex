defmodule ChessDuelBackendWeb.GamesChannel do
  use ChessDuelBackendWeb, :channel

  @impl true
  def join("games:lobby", _payload, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: "pong"}}, socket}
  end
end
