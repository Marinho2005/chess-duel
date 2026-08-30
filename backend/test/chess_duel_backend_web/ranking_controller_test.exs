defmodule ChessDuelBackendWeb.RankingControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: true

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Repo

  test "lista apenas jogadores confirmados por rating e pagina em grupos de 50", %{conn: conn} do
    for index <- 1..52 do
      {:ok, user} =
        Accounts.register_user(%{
          email: "rank#{index}@example.com",
          nickname: "rank_#{index}",
          password: "password1234"
        })

      user
      |> User.confirm_changeset()
      |> Ecto.Changeset.change(rating: 1_000 + index)
      |> Repo.update!()
    end

    {:ok, _unconfirmed} =
      Accounts.register_user(%{
        email: "pending@example.com",
        nickname: "pending_player",
        password: "password1234"
      })

    first_page = conn |> get("/api/ranking?page=1") |> json_response(200)

    assert length(first_page["players"]) == 50

    assert first_page["pagination"] == %{
             "page" => 1,
             "page_size" => 50,
             "total" => 52,
             "total_pages" => 2
           }

    assert hd(first_page["players"])["nickname"] == "rank_52"
    refute Enum.any?(first_page["players"], &(&1["nickname"] == "pending_player"))

    second_page = build_conn() |> get("/api/ranking?page=2") |> json_response(200)
    assert length(second_page["players"]) == 2
    assert second_page["pagination"]["page"] == 2
  end

  test "usa a primeira pagina quando o parametro e invalido", %{conn: conn} do
    response = conn |> get("/api/ranking?page=invalid") |> json_response(200)
    assert response["pagination"]["page"] == 1
  end
end
