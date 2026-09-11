defmodule ChessDuelBackendWeb.AdminControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: false
  import Ecto.Query
  alias ChessDuelBackend.{Accounts, Admin, Games, Repo}
  alias ChessDuelBackend.Accounts.{User, ModerationAction}
  alias ChessDuelBackendWeb.{UserSocket, GamesChannel}
  require Phoenix.ChannelTest

  setup do
    admin = create_user("admin") |> set_fields(role: :admin)
    user = create_user("member")

    %{
      admin: admin,
      user: user,
      admin_token: Accounts.generate_user_api_token(admin),
      user_token: Accounts.generate_user_api_token(user)
    }
  end

  test "all admin endpoints require authentication and administrative role", ctx do
    for {method, path} <- [
          {:get, "/dashboard"},
          {:get, "/users"},
          {:get, "/users/#{ctx.user.id}"},
          {:post, "/users/#{ctx.user.id}/suspend"},
          {:post, "/users/#{ctx.user.id}/ban"},
          {:post, "/users/#{ctx.user.id}/reactivate"},
          {:get, "/games"},
          {:get, "/games/#{Ecto.UUID.generate()}"},
          {:get, "/system"}
        ] do
      assert build_conn() |> dispatch(@endpoint, method, "/api/admin" <> path) |> json_response(401)

      assert conn(ctx.user_token)
             |> dispatch(@endpoint, method, "/api/admin" <> path)
             |> json_response(403)
    end
  end

  test "moderation is audited and old tokens cannot bypass restrictions", ctx do
    ChessDuelBackendWeb.Endpoint.subscribe("users_socket:#{ctx.user.id}")
    until = DateTime.add(DateTime.utc_now(), 3600) |> DateTime.to_iso8601()

    response =
      conn(ctx.admin_token)
      |> post("/api/admin/users/#{ctx.user.id}/suspend", %{
        reason: " Abuso ",
        suspended_until: until
      })
      |> json_response(200)

    assert response["user"]["account_status"] == "suspended"
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    assert conn(ctx.user_token) |> get("/api/users/me") |> json_response(403) |> Map.get("error") ==
             "account_suspended"

    assert :error = Phoenix.ChannelTest.connect(UserSocket, %{"token" => ctx.user_token})

    assert build_conn()
           |> post("/api/users/log_in", %{email: ctx.user.email, password: "password1234"})
           |> json_response(403)
           |> Map.get("error") == "account_suspended"

    assert Repo.one!(ModerationAction).reason == "Abuso"

    assert conn(ctx.admin_token)
           |> post("/api/admin/users/#{ctx.user.id}/ban", %{reason: "Reincidência"})
           |> json_response(200)

    assert conn(ctx.user_token) |> get("/api/users/me") |> json_response(403) |> Map.get("error") ==
             "account_banned"

    assert conn(ctx.user_token) |> get("/api/users/#{ctx.admin.nickname}") |> json_response(403)

    assert conn(ctx.admin_token)
           |> post("/api/admin/users/#{ctx.user.id}/reactivate", %{reason: "Revisão concluída"})
           |> json_response(200)

    assert conn(ctx.user_token) |> get("/api/users/me") |> json_response(200)
    assert Repo.aggregate(ModerationAction, :count) == 3
    assert Accounts.get_user(ctx.user.id).blitz_rating == ctx.user.blitz_rating
    assert Accounts.get_user(ctx.user.id).suspended_until == nil
  end

  test "invalid actions leave both account and audit unchanged", ctx do
    for {action, params} <- [
          {"suspend", %{reason: "", suspended_until: DateTime.add(DateTime.utc_now(), 3600)}},
          {"suspend",
           %{reason: "Motivo", suspended_until: DateTime.add(DateTime.utc_now(), -3600)}},
          {"suspend", %{reason: "Motivo"}},
          {"suspend", %{reason: "Motivo", suspended_until: "invalid"}},
          {"ban", %{reason: "   "}},
          {"ban", %{reason: []}}
        ] do
      assert conn(ctx.admin_token)
             |> post("/api/admin/users/#{ctx.user.id}/#{action}", params)
             |> json_response(422)
    end

    for action <- ~w(suspend ban reactivate) do
      assert conn(ctx.admin_token)
             |> post("/api/admin/users/#{ctx.admin.id}/#{action}", %{reason: "Test"})
             |> json_response(409)
    end

    assert Repo.aggregate(ModerationAction, :count) == 0
    assert Accounts.get_user(ctx.user.id).account_status == :active
    assert {:ok, _} = Admin.moderate(ctx.admin.id, ctx.user.id, :ban, %{"reason" => "Test"})

    assert conn(ctx.admin_token)
           |> post("/api/admin/users/#{ctx.user.id}/reactivate", %{reason: ""})
           |> json_response(422)

    assert Accounts.get_user(ctx.user.id).account_status == :banned
    assert Repo.aggregate(ModerationAction, :count) == 1
  end

  test "expired suspensions are active consistently in auth and filters", ctx do
    set_fields(ctx.user,
      account_status: :suspended,
      suspended_until: DateTime.add(DateTime.utc_now(), -1)
    )

    assert conn(ctx.user_token)
           |> get("/api/users/me")
           |> json_response(200)
           |> get_in(["user", "account_status"]) == "active"

    assert {:ok, _} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => ctx.user_token})

    body =
      conn(ctx.admin_token)
      |> get("/api/admin/users", %{status: "active", q: ctx.user.email})
      |> json_response(200)

    assert Enum.map(body["users"], & &1["id"]) == [ctx.user.id]

    assert conn(ctx.admin_token)
           |> get("/api/admin/users", %{status: "suspended"})
           |> json_response(200)
           |> Map.get("users") == []
  end

  test "stale sockets are refused at join and before handling input", ctx do
    {:ok, socket} = Phoenix.ChannelTest.connect(UserSocket, %{"token" => ctx.user_token})
    {:ok, _} = Admin.moderate(ctx.admin.id, ctx.user.id, :ban, %{"reason" => "Test"})
    assert {:error, %{error: "account_banned"}} = GamesChannel.join("games:lobby", %{}, socket)

    assert {:stop, :normal, {:error, %{error: "account_banned"}}, ^socket} =
             GamesChannel.handle_in("set_presence", %{"status" => "online"}, socket)
  end

  test "blocked admins lose access and the context rechecks current authorization", ctx do
    set_fields(ctx.admin, account_status: :banned)
    assert conn(ctx.admin_token) |> get("/api/admin/dashboard") |> json_response(403)

    assert {:error, :forbidden} =
             Admin.moderate(ctx.admin.id, ctx.user.id, :ban, %{"reason" => "Test"})

    set_fields(ctx.admin, account_status: :active, role: :user)

    assert {:error, :forbidden} =
             Admin.moderate(ctx.admin.id, ctx.user.id, :ban, %{"reason" => "Test"})

    assert Repo.aggregate(ModerationAction, :count) == 0
  end

  test "profile and registration cannot assign privileged fields", ctx do
    assert conn(ctx.user_token)
           |> patch("/api/users/me", %{
             user: %{
               nickname: ctx.user.nickname,
               role: "admin",
               account_status: "banned",
               suspended_until: DateTime.add(DateTime.utc_now(), 3600)
             }
           })
           |> json_response(200)

    assert %User{role: :user, account_status: :active, suspended_until: nil} =
             Accounts.get_user(ctx.user.id)

    {:ok, fresh} =
      Accounts.register_user(%{
        email: "forged@example.com",
        nickname: "forged",
        password: "password1234",
        role: "admin",
        account_status: "banned",
        suspended_until: DateTime.utc_now()
      })

    assert fresh.role == :user and fresh.account_status == :active and fresh.suspended_until == nil
  end

  test "user search is paginated, private and accepts email or nickname", ctx do
    body =
      conn(ctx.admin_token)
      |> get("/api/admin/users", %{q: "MEMBER", per_page: "1"})
      |> json_response(200)

    assert body["pagination"]["total"] == 1
    assert hd(body["users"])["email"] == ctx.user.email
    detail = conn(ctx.admin_token) |> get("/api/admin/users/#{ctx.user.id}")
    assert get_resp_header(detail, "cache-control") == ["no-store"]
    body = json_response(detail, 200)
    refute Map.has_key?(body["user"], "hashed_password")
    refute Map.has_key?(body["user"], "birth_date")
    assert body["game_summary"]["total_games"] == 0

    assert conn(ctx.admin_token)
           |> get("/api/admin/users", %{status: "invalid"})
           |> json_response(400)

    assert conn(ctx.admin_token) |> get("/api/admin/users/not-a-uuid") |> json_response(404)

    assert conn(ctx.admin_token)
           |> post("/api/admin/users/not-a-uuid/ban", %{reason: "Test"})
           |> json_response(404)

    refute conn(ctx.user_token)
           |> get("/api/users/#{ctx.admin.nickname}")
           |> json_response(200)
           |> get_in(["profile", "role"])
  end

  test "games queries include bots, snapshots and analysis without mutations", ctx do
    {:ok, game} =
      Games.create_game(%{
        game_id: "admin-game",
        white_player_id: ctx.user.id,
        black_player_id: "bot:clark",
        bot_id: "clark",
        bot_color: "black",
        status: "finished",
        result: "white_wins",
        end_reason: "checkmate",
        finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    game
    |> Ecto.Changeset.change(white_rating_before: 1300, white_rating_after: 1300)
    |> Repo.update!()

    %ChessDuelBackend.GameAnalysis.Analysis{}
    |> ChessDuelBackend.GameAnalysis.Analysis.changeset(%{game_id: game.id})
    |> Repo.insert!()

    body =
      conn(ctx.admin_token)
      |> get("/api/admin/games", %{
        type: "bot",
        status: "finished",
        q: "member",
        from: Date.to_iso8601(Date.utc_today())
      })
      |> json_response(200)

    assert body["pagination"]["total"] == 1
    data = hd(body["games"])
    assert data["white"]["rating_before"] == 1300
    assert data["black"]["nickname"] == "Clark"
    assert data["analysis"]["status"] == "pending"
    refute Map.has_key?(data, "moves")

    assert conn(ctx.admin_token)
           |> get("/api/admin/games/#{game.id}")
           |> json_response(200)
           |> get_in(["game", "moves"]) == []

    assert conn(ctx.admin_token)
           |> get("/api/admin/games", %{type: "human"})
           |> json_response(200)
           |> Map.get("games") == []

    assert conn(ctx.admin_token) |> get("/api/admin/games", %{from: "bad"}) |> json_response(400)
    assert conn(ctx.admin_token) |> get("/api/admin/games/not-a-uuid") |> json_response(404)
    {:ok, _} = Admin.moderate(ctx.admin.id, ctx.user.id, :ban, %{"reason" => "Test"})
    assert Repo.get!(Games.Game, game.id).result == "white_wins"
  end

  test "dashboard and system count actual analysis jobs", ctx do
    %{analysis_id: Ecto.UUID.generate()}
    |> ChessDuelBackend.GameAnalysis.Job.new()
    |> Oban.insert!()

    body = conn(ctx.admin_token) |> get("/api/admin/dashboard") |> json_response(200)
    assert body["total_users"] == 2
    assert body["pending_analysis_jobs"] == 1
    assert body["failed_analysis_jobs"] == 0
    Repo.update_all(from(j in Oban.Job), set: [state: "discarded"])
    body = conn(ctx.admin_token) |> get("/api/admin/system") |> json_response(200)
    assert body["database"] == "available"
    assert body["analysis_jobs"]["failed_analysis_jobs"] == 1
    assert body["analysis_jobs"]["pending_analysis_jobs"] == 0
  end

  defp create_user(name) do
    {:ok, user} =
      Accounts.register_user(%{
        email: "#{name}@example.com",
        nickname: name,
        password: "password1234"
      })

    user |> User.confirm_changeset() |> Repo.update!()
  end

  defp set_fields(user, attrs), do: user |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp conn(token), do: build_conn() |> put_req_header("authorization", "Bearer " <> token)
end
