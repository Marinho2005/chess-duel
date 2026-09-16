defmodule ChessDuelBackend.DeploymentConfigTest do
  use ExUnit.Case, async: false

  @env %{
    "PHX_HOST" => "api.chessduel.app",
    "FRONTEND_URL" => "https://chessduel.app",
    "ALLOWED_ORIGINS" => " https://chessduel.app, https://www.chessduel.app ",
    "DATABASE_URL" => "postgres://test:test@db.internal:5432/test",
    "DATABASE_SSL_MODE" => "disable",
    "DATABASE_CA_CERTFILE" => "/tmp/test-ca.pem",
    "SECRET_KEY_BASE" => String.duplicate("test-only", 8),
    "VALKEY_URL" => "redis://cache.internal:6379",
    "UPLOADS_DIR" => "/data/uploads",
    "PORT" => "4567",
    "POOL_SIZE" => "3",
    "STOCKFISH_PATH" => "/custom/stockfish"
  }

  setup do
    previous = Map.new(@env, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(@env)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    :ok
  end

  defp runtime,
    do: Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)[:chess_duel_backend]

  test "runtime shares exact origins with CORS and WebSocket and configures uploads" do
    config = runtime()
    endpoint = config[ChessDuelBackendWeb.Endpoint]
    assert endpoint[:check_origin] == config[:cors][:origin]
    assert config[:cors][:origin] == ["https://chessduel.app", "https://www.chessduel.app"]
    assert endpoint[:url] == [host: "api.chessduel.app", scheme: "https", port: 443]
    assert endpoint[:http][:port] == 4567
    assert config[:avatar_upload_dir] == "/data/uploads/avatars"
    assert config[:club_avatar_upload_dir] == "/data/uploads/clubs"
    assert config[:stockfish][:path] == "/custom/stockfish"

    System.put_env("ALLOWED_ORIGINS", "https://chessduel.app,https://preview.example")
    assert "https://preview.example" in runtime()[:cors][:origin]
  end

  test "production compile config requires no environment variables" do
    Enum.each(@env, fn {key, _} -> System.delete_env(key) end)
    config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)
    endpoint = config[:chess_duel_backend][ChessDuelBackendWeb.Endpoint]
    assert endpoint[:force_ssl][:rewrite_on] == [:x_forwarded_proto]
    refute endpoint[:secret_key_base]
  end

  test "TLS mode is explicit and has no silent insecure fallback" do
    assert runtime()[ChessDuelBackend.Repo][:ssl] == false
    System.put_env("DATABASE_SSL_MODE", "require")
    assert runtime()[ChessDuelBackend.Repo][:ssl] == [verify: :verify_none]
    System.put_env("DATABASE_SSL_MODE", "verify-full")
    opts = runtime()[ChessDuelBackend.Repo][:ssl]
    assert opts[:verify] == :verify_peer
    assert opts[:server_name_indication] == ~c"db.internal"
    assert opts[:cacertfile] == "/tmp/test-ca.pem"
    System.delete_env("DATABASE_SSL_MODE")
    assert_raise RuntimeError, ~r/DATABASE_SSL_MODE/, &runtime/0
  end

  test "unsafe origins and invalid required settings fail at startup" do
    for invalid <- ["*", "http://chessduel.app", "https://chessduel.app/path"] do
      System.put_env("ALLOWED_ORIGINS", invalid)
      assert_raise RuntimeError, &runtime/0
    end

    System.put_env("ALLOWED_ORIGINS", @env["ALLOWED_ORIGINS"])
    System.put_env("PORT", "invalid")
    assert_raise RuntimeError, ~r/PORT/, &runtime/0
    System.put_env("PORT", "4000")
    System.put_env("UPLOADS_DIR", "/")
    assert_raise RuntimeError, ~r/UPLOADS_DIR/, &runtime/0
  end

  test "database URL cannot silently override the explicit TLS mode" do
    System.put_env("DATABASE_URL", "postgres://test:test@db.internal/test?ssl=false")
    assert_raise RuntimeError, ~r/DATABASE_SSL_MODE/, &runtime/0
  end
end
