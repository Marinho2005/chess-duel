defmodule ChessDuelBackendWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.AccountAccess

  def init(action), do: action

  def call(conn, :fetch_current_user), do: fetch_current_user(conn, [])
  def call(conn, :require_authenticated_user), do: require_authenticated_user(conn, [])
  def call(conn, :require_admin), do: require_admin(conn, [])

  def fetch_current_user(conn, _opts) do
    with {:ok, encoded_token} <- bearer_token(conn),
         {user, _token_inserted_at} <- Accounts.get_user_by_api_token(encoded_token) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_user_token, encoded_token)
      |> require_active_user()
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  def require_active_user(conn) do
    case AccountAccess.check(conn.assigns[:current_user]) do
      :ok -> conn
      {:error, error} -> conn |> put_status(:forbidden) |> json(error) |> halt()
    end
  end

  def require_admin(conn, _opts) do
    if AccountAccess.admin?(conn.assigns[:current_user]) do
      conn
    else
      conn |> put_status(:forbidden) |> json(%{error: "admin_required"}) |> halt()
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "authentication_required"})
      |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> :error
    end
  end
end
