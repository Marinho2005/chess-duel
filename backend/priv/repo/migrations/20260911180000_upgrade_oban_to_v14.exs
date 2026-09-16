defmodule ChessDuelBackend.Repo.Migrations.UpgradeObanToV14 do
  use Ecto.Migration

  # O lock atual usa Oban 2.24; bancos novos ainda paravam no schema v12.
  def up, do: Oban.Migration.up(version: 14)
  # down remove as versoes indicadas inclusive: remover 14 e 13 restaura v12.
  def down, do: Oban.Migration.down(version: 13)
end
