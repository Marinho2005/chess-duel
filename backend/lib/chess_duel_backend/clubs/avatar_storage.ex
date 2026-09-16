defmodule ChessDuelBackend.Clubs.AvatarStorage do
  @max_size 2 * 1024 * 1024
  @prefix "/uploads/clubs/"

  def save(%Plug.Upload{path: temporary_path}, club_id) do
    with {:ok, %{size: size}} when size <= @max_size <- File.stat(temporary_path),
         {:ok, contents} <- File.read(temporary_path),
         {:ok, extension} <- extension(contents),
         directory = directory(),
         filename = "#{club_id}-#{Ecto.UUID.generate()}.#{extension}",
         :ok <- File.mkdir_p(directory),
         :ok <- File.write(Path.join(directory, filename), contents, [:binary]) do
      {:ok, @prefix <> filename}
    else
      {:ok, %{size: _}} -> {:error, :file_too_large}
      {:error, :invalid_image} -> {:error, :invalid_image}
      _ -> {:error, :upload_failed}
    end
  end

  def delete(@prefix <> filename) do
    if Path.basename(filename) == filename, do: File.rm(Path.join(directory(), filename))
    :ok
  end

  def delete(_), do: :ok

  defp directory do
    Application.get_env(
      :chess_duel_backend,
      :club_avatar_upload_dir,
      Application.app_dir(:chess_duel_backend, "priv/static/uploads/clubs")
    )
  end

  defp extension(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "jpg"}
  defp extension(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: {:ok, "png"}
  defp extension(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: {:ok, "webp"}
  defp extension(_), do: {:error, :invalid_image}
end
