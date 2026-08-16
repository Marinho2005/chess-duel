defmodule ChessDuelBackendWeb.Router do
  use ChessDuelBackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

end
