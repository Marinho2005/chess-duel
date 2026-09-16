defmodule ChessDuelBackendWeb.DeploymentPlugsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  alias ChessDuelBackendWeb.Plugs.{RuntimeCors, UploadStatic}

  setup do
    keys = [:cors, :uploads_dir, :avatar_upload_dir, :club_avatar_upload_dir]
    previous = Map.new(keys, &{&1, Application.fetch_env(:chess_duel_backend, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:chess_duel_backend, key, value)
        {key, :error} -> Application.delete_env(:chess_duel_backend, key)
      end)
    end)

    :ok
  end

  test "already initialized CORS plug reads changed origins, including preflight" do
    opts = RuntimeCors.init([])
    Application.put_env(:chess_duel_backend, :cors, origin: ["https://one.example"])

    request =
      conn(:options, "/api/health")
      |> put_req_header("origin", "https://one.example")
      |> put_req_header("access-control-request-method", "GET")

    assert get_resp_header(RuntimeCors.call(request, opts), "access-control-allow-origin") == [
             "https://one.example"
           ]

    Application.put_env(:chess_duel_backend, :cors, origin: ["https://two.example"])
    assert get_resp_header(RuntimeCors.call(request, opts), "access-control-allow-origin") == []
    response = request |> put_req_header("origin", "https://two.example") |> RuntimeCors.call(opts)
    assert response.status == 204
    assert get_resp_header(response, "access-control-allow-origin") == ["https://two.example"]
  end

  test "production SSL recognizes proxy HTTPS and excludes only health from redirect" do
    opts =
      Config.Reader.read!("config/prod.exs", env: :prod, target: :host)[:chess_duel_backend][
        ChessDuelBackendWeb.Endpoint
      ][:force_ssl]
      |> Keyword.put(:host, "api.chessduel.app")
      |> Plug.SSL.init()

    response =
      conn(:get, "http://api.chessduel.app/api/games/live")
      |> put_req_header("x-forwarded-proto", "https")
      |> Plug.SSL.call(opts)

    assert response.scheme == :https
    refute response.halted
    assert get_resp_header(response, "strict-transport-security") != []
    redirect = conn(:get, "http://untrusted.example/api/games/live") |> Plug.SSL.call(opts)
    assert get_resp_header(redirect, "location") == ["https://api.chessduel.app/api/games/live"]
    health = conn(:get, "http://healthcheck.railway.app/api/health") |> Plug.SSL.call(opts)
    refute health.halted
  end

  test "both avatar stores write to runtime root and static plug serves their files" do
    root =
      Path.join(System.tmp_dir!(), "chessduel-uploads-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    Application.put_env(:chess_duel_backend, :uploads_dir, root)
    Application.put_env(:chess_duel_backend, :avatar_upload_dir, Path.join(root, "avatars"))
    Application.put_env(:chess_duel_backend, :club_avatar_upload_dir, Path.join(root, "clubs"))
    source = Path.join(root, "input.png")
    bytes = <<0x89, "PNG\r\n", 0x1A, "\n", 0, 1>>
    File.write!(source, bytes)
    upload = %Plug.Upload{path: source, filename: "input.png"}

    for store <- [ChessDuelBackend.Accounts.AvatarStorage, ChessDuelBackend.Clubs.AvatarStorage] do
      assert {:ok, path} = store.save(upload, Ecto.UUID.generate())
      response = conn(:get, path) |> UploadStatic.call(UploadStatic.init([]))
      assert response.status == 200
      assert response.resp_body == bytes
    end
  end
end
