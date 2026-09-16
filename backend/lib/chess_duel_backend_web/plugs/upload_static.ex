defmodule ChessDuelBackendWeb.Plugs.UploadStatic do
  @moduledoc "Serve o diretorio de uploads definido em runtime."
  @behaviour Plug
  def init(options), do: options

  def call(conn, _options) do
    directory =
      Application.get_env(
        :chess_duel_backend,
        :uploads_dir,
        Application.app_dir(:chess_duel_backend, "priv/static/uploads")
      )

    options = Plug.Static.init(at: "/uploads", from: directory, gzip: false)
    Plug.Static.call(conn, options)
  end
end
