defmodule PlanningPoker.Repo.Migrations.CreateVotings do
  use Ecto.Migration

  def change do
    create table(:votings) do
      add :title, :string, null: false
      add :link, :string
      add :description, :text
      add :decision, :string
      add :votes, {:array, :map}, default: [], null: false
      add :position, :integer, null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:votings, [:game_id, :position])
  end
end
