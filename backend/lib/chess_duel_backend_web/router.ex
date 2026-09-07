defmodule ChessDuelBackendWeb.Router do
  use ChessDuelBackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug ChessDuelBackendWeb.UserAuth, :fetch_current_user
    plug ChessDuelBackendWeb.UserAuth, :require_authenticated_user
  end

  pipeline :optional_authenticated_api do
    plug ChessDuelBackendWeb.UserAuth, :fetch_current_user
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
    get "/ranking", UserController, :ranking
    get "/games/live", LiveGameController, :index
    get "/broadcasts/live", BroadcastController, :index
    get "/broadcasts/tournaments", BroadcastController, :tournaments
    get "/broadcasts/tournaments/:tournament_id", BroadcastController, :tournament
    get "/broadcasts/rounds/:round_id/games", BroadcastController, :round_games
    get "/broadcasts/tournaments/:tournament_id/games", BroadcastController, :tournament_games
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through [:api, :authenticated_api]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/me", UserController, :me
    get "/users/search", FriendshipController, :search
    get "/friendships", FriendshipController, :index
    post "/friendships", FriendshipController, :create
    patch "/friendships/:id/accept", FriendshipController, :accept
    patch "/friendships/:id/decline", FriendshipController, :decline
    delete "/friendships/:id", FriendshipController, :delete
    get "/clubs", ClubController, :index
    post "/clubs", ClubController, :create
    get "/clubs/:id", ClubController, :show
    patch "/clubs/:id", ClubController, :update
    post "/clubs/:id/join", ClubController, :join
    patch "/clubs/:id/memberships/:membership_id/approve", ClubController, :approve
    patch "/clubs/:id/memberships/:membership_id/decline", ClubController, :decline
    patch "/clubs/:id/memberships/:membership_id/promote", ClubController, :promote
    delete "/clubs/:id/memberships/:membership_id", ClubController, :delete_membership
    get "/users/me/games", GameHistoryController, :index
    get "/bots", BotGameController, :index
    post "/bot-games", BotGameController, :create
    post "/games/:id/analyze", GameAnalysisController, :create
    get "/games/:id/analysis", GameAnalysisController, :show
    get "/puzzles/next", PuzzleController, :next
    get "/puzzles/summary", PuzzleController, :summary
    post "/puzzles/:id/attempt", PuzzleController, :attempt
    post "/puzzle_rush/start", PuzzleRushController, :start
    get "/puzzle_rush/:session_id", PuzzleRushController, :show
    post "/puzzle_rush/:session_id/attempt", PuzzleRushController, :attempt
    patch "/users/me", UserController, :update
    post "/users/me/avatar", UserController, :update_avatar
  end

  scope "/api", ChessDuelBackendWeb do
    pipe_through [:api, :optional_authenticated_api]

    get "/profiles/:nickname", UserController, :show
    get "/users/:nickname", UserController, :show
  end
end
