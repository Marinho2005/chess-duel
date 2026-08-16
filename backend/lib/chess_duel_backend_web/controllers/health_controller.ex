defmodule ChessDuelBackendWeb.HealthController do
  use ChessDuelBackendWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
