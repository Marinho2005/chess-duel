defmodule ChessDuelBackendWeb.GameHistoryController do
  use ChessDuelBackendWeb, :controller

  alias ChessDuelBackend.Games

  def index(conn, params) do
    history =
      Games.list_finished_games_for_user(conn.assigns.current_user.id,
        page: positive_integer(params["page"], 1),
        per_page: positive_integer(params["per_page"], 10)
      )

    json(conn, history)
  end

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  defp positive_integer(_value, default), do: default
end
