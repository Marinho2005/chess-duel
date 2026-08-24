defmodule ChessDuelBackend.Accounts.UserNotifier do
  require Logger
  alias ChessDuelBackend.Accounts.User

  defp deliver(recipient, subject, body) do
    Logger.info("""
    [ChessDuel email - desenvolvimento]
    Para: #{recipient}
    Assunto: #{subject}
    #{body}
    """)

    {:ok, %{to: recipient, subject: subject, body: body}}
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirme sua conta ChessDuel", """

    ==============================

    Ola #{user.email},

    Confirme sua conta acessando o link abaixo:

    #{url}

    Se voce nao criou esta conta, ignore esta mensagem.

    ==============================
    """)
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end
end
