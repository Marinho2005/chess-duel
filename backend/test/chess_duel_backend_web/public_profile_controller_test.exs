defmodule ChessDuelBackendWeb.PublicProfileControllerTest do
  use ChessDuelBackendWeb.ConnCase, async: true

  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.User
  alias ChessDuelBackend.Repo

  test "retorna as abas e conta somente a visita autenticada de outro jogador", %{conn: conn} do
    owner = confirmed_user!("profile-owner@example.com", "profile_owner")
    visitor = confirmed_user!("profile-visitor@example.com", "profile_visitor")

    anonymous = conn |> get("/api/users/#{owner.nickname}") |> json_response(200)
    assert anonymous["profile"]["profile_views"] == 0
    assert anonymous["profile"]["games"] == []
    assert anonymous["profile"]["friends"] == []
    assert anonymous["profile"]["clubs"] == []
    assert is_list(anonymous["profile"]["rating_history"])

    own_token = Accounts.generate_user_api_token(owner)

    own =
      build_conn()
      |> put_req_header("authorization", "Bearer #{own_token}")
      |> get("/api/users/#{owner.nickname}")
      |> json_response(200)

    assert own["profile"]["profile_views"] == 0

    visitor_token = Accounts.generate_user_api_token(visitor)

    visited =
      build_conn()
      |> put_req_header("authorization", "Bearer #{visitor_token}")
      |> get("/api/users/#{owner.nickname}")
      |> json_response(200)

    assert visited["profile"]["profile_views"] == 1

    refreshed =
      build_conn()
      |> put_req_header("authorization", "Bearer #{visitor_token}")
      |> get("/api/users/#{owner.nickname}?count_view=false")
      |> json_response(200)

    assert refreshed["profile"]["profile_views"] == 1
  end

  defp confirmed_user!(email, nickname) do
    {:ok, user} =
      Accounts.register_user(%{email: email, nickname: nickname, password: "password1234"})

    user |> User.confirm_changeset() |> Repo.update!()
  end
end
