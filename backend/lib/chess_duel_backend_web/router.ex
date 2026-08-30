defmodule ChessDuelBackendWeb.Router do
  use ChessDuelBackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug ChessDuelBackendWeb.UserAuth, :fetch_current_user
    plug ChessDuelBackendWeb.UserAuth, :require_authenticated_user
  end

  pipeline :oauth do
    plug :fetch_session
  end

  scope "/auth", ChessDuelBackendWeb do
    pipe_through :oauth

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through :api

    get "/health", HealthController, :index
    post "/guests/session", GuestSessionController, :create
    post "/users/register", UserRegistrationController, :create
    post "/users/confirm/:token", UserConfirmationController, :create
    post "/users/log_in", UserSessionController, :create
    get "/profiles/:nickname", UserController, :show
    get "/ranking", UserController, :ranking
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through [:api, :authenticated_api]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/me", UserController, :me
    get "/users/me/games", GameHistoryController, :index
    get "/bots", BotGameController, :index
    post "/bot-games", BotGameController, :create
    post "/games/:id/analyze", GameAnalysisController, :create
    get "/games/:id/analysis", GameAnalysisController, :show
    patch "/users/me", UserController, :update
    post "/users/me/avatar", UserController, :update_avatar
  end
end
