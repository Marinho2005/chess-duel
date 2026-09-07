defmodule ChessDuelBackendWeb.UserJSON do
  def data(user) do
    %{
      id: user.id,
      email: user.email,
      nickname: user.nickname,
      country: user.country,
      country_code: user.country_code,
      avatar_url: user.avatar_path,
      rating: user.blitz_rating,
      ratings: ChessDuelBackend.Accounts.User.ratings(user),
      birth_date: user.birth_date,
      inserted_at: user.inserted_at
    }
  end

  def public_data(user, extras \\ %{}) do
    %{
      id: user.id,
      nickname: user.nickname,
      country: user.country,
      country_code: user.country_code,
      avatar_url: user.avatar_path,
      rating: user.blitz_rating,
      ratings: ChessDuelBackend.Accounts.User.ratings(user),
      inserted_at: user.inserted_at
    }
    |> Map.merge(extras)
  end

  def ranking_data(user, category \\ :blitz) do
    %{
      id: user.id,
      nickname: user.nickname,
      country_code: user.country_code,
      avatar_url: user.avatar_path,
      rating: ChessDuelBackend.Accounts.User.rating_for(user, category)
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
