defmodule ChessDuelBackendWeb.UserJSON do
  def data(user) do
    %{
      id: user.id,
      email: user.email,
      nickname: user.nickname,
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
