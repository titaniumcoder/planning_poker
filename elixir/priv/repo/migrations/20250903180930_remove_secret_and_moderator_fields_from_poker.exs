defmodule PlanningPoker.Repo.Migrations.RemoveSecretAndModeratorFieldsFromPoker do
  use Ecto.Migration

  def change do
    alter table(:poker) do
      remove :secret_hashed, :string
      remove :all_moderators, :boolean
    end
  end
end
