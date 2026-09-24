defmodule PlanningPoker.Repo.Migrations.AddClosedAtToPoker do
  use Ecto.Migration

  def change do
    alter table(:poker) do
      add :closed_at, :utc_datetime
    end
  end
end
