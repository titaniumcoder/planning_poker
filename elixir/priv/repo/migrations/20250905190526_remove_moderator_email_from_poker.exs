defmodule PlanningPoker.Repo.Migrations.RemoveModeratorEmailFromPoker do
  use Ecto.Migration

  def change do
    alter table(:poker) do
      remove :moderator_email, :string
    end
  end
end
