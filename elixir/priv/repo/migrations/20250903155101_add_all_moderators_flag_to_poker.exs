defmodule PlanningPoker.Repo.Migrations.AddAllModeratorsFlagToPoker do
  use Ecto.Migration

  def change do
    alter table(:poker) do
      add :all_moderators, :boolean, default: true, null: false
    end
  end
end
