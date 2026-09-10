defmodule ChessDuelBackend.Accounts.AccountAccess do
  @moduledoc "Regra única de acesso; suspensão expirada não exige escrita nem job."
  alias ChessDuelBackend.Accounts.User

  def status(user, now \\ DateTime.utc_now())

  def status(%User{account_status: :suspended, suspended_until: %DateTime{} = until}, now) do
    if DateTime.compare(until, now) == :gt, do: :suspended, else: :active
  end

  def status(%User{account_status: status}, _now), do: status

  def check(%User{} = user) do
    case status(user) do
      :active ->
        :ok

      :banned ->
        {:error, %{error: "account_banned", message: "Sua conta foi banida."}}

      :suspended ->
        {:error,
         %{
           error: "account_suspended",
           suspended_until: user.suspended_until,
           message: "Sua conta está suspensa temporariamente."
         }}
    end
  end

  def check(_), do: {:error, %{error: "authentication_required", message: "Entre novamente."}}

  def admin?(%User{role: :admin} = user), do: check(user) == :ok
  def admin?(_), do: false
end
