defmodule ChessDuelBackend.Accounts.AvatarStorage do
  @moduledoc "Armazena avatares locais com validacao de tamanho e assinatura do arquivo."

  @max_size 2 * 1024 * 1024
  @public_prefix "/uploads/avatars/"

  def save(%Plug.Upload{path: temporary_path}, user_id) do
    with {:ok, %{size: size}} when size <= @max_size <- File.stat(temporary_path),
         {:ok, contents} <- File.read(temporary_path),
         {:ok, extension} <- image_extension(contents) do
      directory = upload_directory()
      filename = "#{user_id}-#{Ecto.UUID.generate()}.#{extension}"

      with :ok <- File.mkdir_p(directory),
           :ok <- File.write(Path.join(directory, filename), contents, [:binary]) do
        {:ok, @public_prefix <> filename}
      end
    else
      {:ok, %{size: _size}} -> {:error, :file_too_large}
      {:error, :invalid_image} -> {:error, :invalid_image}
      _ -> {:error, :upload_failed}
    end
  end

  def delete(nil), do: :ok

  def delete(@public_prefix <> filename) do
    if Path.basename(filename) == filename do
      File.rm(Path.join(upload_directory(), filename))
      :ok
    else
      :ok
    end
  end

  def delete(_path), do: :ok

  defp upload_directory do
    Application.get_env(
      :chess_duel_backend,
      :avatar_upload_dir,
      Application.app_dir(:chess_duel_backend, "priv/static/uploads/avatars")
    )
  end

  defp image_extension(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "jpg"}
  defp image_extension(<<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: {:ok, "png"}
  defp image_extension(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: {:ok, "webp"}
  defp image_extension(_contents), do: {:error, :invalid_image}
end
