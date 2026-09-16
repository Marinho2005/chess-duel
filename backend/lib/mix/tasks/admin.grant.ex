defmodule Mix.Tasks.Admin.Grant do
  use Mix.Task
  @shortdoc "Concede acesso administrativo a uma conta confirmada pelo UUID"
  alias ChessDuelBackend.{Repo, Accounts}
  alias ChessDuelBackend.Accounts.AccountAccess

  def run([id]) do
    Mix.Task.run("app.start")

    with {:ok, id} <- Ecto.UUID.cast(id),
         %Accounts.User{confirmed_at: confirmed} = user when not is_nil(confirmed) <-
           Accounts.get_user(id),
         :ok <- AccountAccess.check(user) do
      user |> Ecto.Changeset.change(role: :admin) |> Repo.update!()
      Mix.shell().info("Acesso administrativo concedido à conta #{id}.")
    else
      _ -> Mix.raise("Informe o UUID de uma conta confirmada e ativa.")
    end
  end

  def run(_), do: Mix.raise("Uso: mix admin.grant UUID_DO_USUARIO")
end
