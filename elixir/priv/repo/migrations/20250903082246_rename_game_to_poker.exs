defmodule PlanningPoker.Repo.Migrations.RenameGameToPoker do
  use Ecto.Migration

  def change do
    rename table("games"), to: table("poker")
  end
end
