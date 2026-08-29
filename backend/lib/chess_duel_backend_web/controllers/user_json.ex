defmodule ChessDuelBackendWeb.UserJSON do
  def data(user) do
    %{
      id: user.id,
      email: user.email,
      nickname: user.nickname,
      country: user.country,
      avatar_url: user.avatar_path,
      rating: user.rating,
      inserted_at: user.inserted_at
    }
  end

  def public_data(user) do
    %{
      id: user.id,
      nickname: user.nickname,
      country: user.country,
      avatar_url: user.avatar_path,
      rating: user.rating,
      inserted_at: user.inserted_at
    }
  end

  def ranking_data(user) do
    %{
      id: user.id,
      nickname: user.nickname,
      avatar_url: user.avatar_path,
      rating: user.rating
    }
  end

  def errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, text ->
        String.replace(text, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
