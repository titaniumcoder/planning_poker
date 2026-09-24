defmodule PlanningPoker.Repo.Migrations.RenameGameIdToPokerIdInVotings do
  use Ecto.Migration

  def change do
    # Drop the existing index
    drop index(:votings, [:game_id, :position])

    # Rename the column (Ecto will handle the foreign key constraint properly)
    rename table(:votings), :game_id, to: :poker_id

    # Create the new index
    create index(:votings, [:poker_id, :position])
  end
end
