defmodule PlanningPoker.Repo.Migrations.AddCardTypeToPoker do
  use Ecto.Migration

  def change do
    alter table(:poker) do
      add :card_type, :string, default: "fibonacci"
    end
  end
end
