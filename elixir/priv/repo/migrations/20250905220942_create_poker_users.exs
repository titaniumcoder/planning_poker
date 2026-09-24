defmodule PlanningPoker.Repo.Migrations.CreatePokerUsers do
  use Ecto.Migration

  def change do
    create table(:poker_users) do
      add :username, :string, null: false
      add :joined_at, :utc_datetime, null: false
      add :left_at, :utc_datetime
      add :muted, :boolean, default: false, null: false
      add :poker_id, references(:poker, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:poker_users, [:poker_id])
    create unique_index(:poker_users, [:poker_id, :username])
  end
end
