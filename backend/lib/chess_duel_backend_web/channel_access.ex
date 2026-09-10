defmodule ChessDuelBackendWeb.ChannelAccess do
  @moduledoc "Aplica a mesma regra a joins e eventos de todos os Channels, inclusive sockets antigos."
  alias ChessDuelBackend.Accounts
  alias ChessDuelBackend.Accounts.AccountAccess

  def check(%{assigns: %{identity_type: :guest}}), do: :ok
  def check(%{assigns: %{user_id: id}}), do: id |> Accounts.get_user() |> AccountAccess.check()
  def check(_), do: AccountAccess.check(nil)

  # O disconnect fecha os sockets existentes. Esta verificação cobre também a
  # corrida entre autenticar o transporte e assinar o tópico de desconexão.
  defmacro __before_compile__(_env) do
    quote do
      defoverridable join: 3, handle_in: 3

      def join(topic, payload, socket) do
        case ChessDuelBackendWeb.ChannelAccess.check(socket) do
          :ok -> super(topic, payload, socket)
          {:error, error} -> {:error, error}
        end
      end

      def handle_in(event, payload, socket) do
        case ChessDuelBackendWeb.ChannelAccess.check(socket) do
          :ok -> super(event, payload, socket)
          {:error, error} -> {:stop, :normal, {:error, error}, socket}
        end
      end
    end
  end
end
