defmodule PlanningPoker.Repo.Migrations.RemoveDescriptionFields do
  use Ecto.Migration

  def change do
    alter table(:poker) do
      remove :description
    end

    alter table(:votings) do
      remove :description
    end
  end
end
