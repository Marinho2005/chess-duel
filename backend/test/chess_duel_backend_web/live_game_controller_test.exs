defmodule ChessDuelBackendWeb.LiveGameControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: false

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Games.{Bots, GameServer}
  alias ChessDuelBackend.Repo

  test "GET /api/games/live returns only current registered human games", %{conn: conn} do
    white = user("live-white")
    black = user("live-black")
    active_id = "live-#{System.unique_integer([:positive])}"
    finished_id = "finished-#{System.unique_integer([:positive])}"
    bot_id = "bot-live-#{System.unique_integer([:positive])}"

    assert {:ok, _} = GameServer.reserve_players(active_id, white.id, black.id)
    assert {:ok, _} = GameServer.reserve_players(finished_id, white.id, black.id)
    assert {:ok, _} = GameServer.reserve_bot_game(bot_id, white.id, Bots.get("clark"), "white", nil)
    wait_until_started(active_id)
    wait_until_started(finished_id)
    wait_until_started(bot_id)
    assert {:ok, _} = GameServer.make_move(active_id, "e2", "e4", white.id)
    assert {:ok, _} = GameServer.resign(finished_id, white.id)

    response = conn |> get("/api/games/live") |> json_response(200)
    assert [%{"game_id" => ^active_id} = game] = response["games"]
    assert game["fen"] =~ " b "
    assert game["current_turn"] == "black"
    assert is_integer(game["white_time_remaining_ms"])
    assert is_integer(game["black_time_remaining_ms"])
    assert game["initial_time_ms"] == 180_000
    assert game["increment_ms"] == 0
    assert game["category"] == "blitz"
    assert game["white"]["nickname"] == white.nickname
    assert game["black"]["nickname"] == black.nickname
    assert game["white"]["status"] == "offline"
    assert Map.has_key?(game["white"], "avatar_url")
    assert Map.has_key?(game["white"], "country_code")

    Process.sleep(150)
    Enum.each([active_id, finished_id, bot_id], &cleanup/1)
  end

  test "GET /api/games/live filters categories and rejects unknown values", %{conn: conn} do
    white = user("filter-white")
    black = user("filter-black")
    bullet_id = "bullet-live-#{System.unique_integer([:positive])}"
    blitz_id = "blitz-live-#{System.unique_integer([:positive])}"
    bullet = %{id: "bullet_1_0", label: "Bullet 1+0", initial_time_ms: 60_000, increment_ms: 0}

    assert {:ok, _} = GameServer.reserve_players(bullet_id, white.id, black.id, bullet)
    assert {:ok, _} = GameServer.reserve_players(blitz_id, white.id, black.id)
    wait_until_started(bullet_id)
    wait_until_started(blitz_id)

    response = conn |> get("/api/games/live?category=bullet") |> json_response(200)
    assert [%{"game_id" => ^bullet_id, "category" => "bullet"}] = response["games"]
    refute Enum.any?(response["games"], &(&1["game_id"] == blitz_id))

    assert %{"error" => "invalid_category"} =
             conn |> recycle() |> get("/api/games/live?category=classical") |> json_response(400)

    Enum.each([bullet_id, blitz_id], &cleanup/1)
  end

  defp user(prefix) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        email: "#{prefix}-#{suffix}@example.com",
        nickname: "#{prefix}_#{suffix}",
        password: "password1234"
      })

    user |> User.confirm_changeset() |> Repo.update!()
  end

  defp wait_until_started(game_id, attempts \\ 20)
  defp wait_until_started(_game_id, 0), do: flunk("game did not start")

  defp wait_until_started(game_id, attempts) do
    case GameServer.get_state(game_id) do
      {:ok, %{status: "in_progress"}} ->
        :ok

      _ ->
        Process.sleep(10)
        wait_until_started(game_id, attempts - 1)
    end
  end

  defp cleanup(game_id) do
    case Registry.lookup(ChessDuelBackend.GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(ChessDuelBackend.GameSupervisor, pid)
      [] -> :ok
    end
  end
end
