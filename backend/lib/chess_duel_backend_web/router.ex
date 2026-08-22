defmodule ChessDuelBackendWeb.Router do
  use ChessDuelBackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug ChessDuelBackendWeb.UserAuth, :fetch_current_user
    plug ChessDuelBackendWeb.UserAuth, :require_authenticated_user
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through :api

    get "/health", HealthController, :index
    post "/users/register", UserRegistrationController, :create
    post "/users/log_in", UserSessionController, :create
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through [:api, :authenticated_api]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/me", UserController, :me
  end
end
