defmodule PlanningPoker.Repo.Migrations.SimplifyPokerUserTracking do
  use Ecto.Migration

  def up do
    # Add usernames array field to poker table
    alter table(:poker) do
      add :usernames, {:array, :string}, default: []
    end

    # Copy existing usernames from poker_users to poker.usernames
    execute """
    UPDATE poker 
    SET usernames = (
      SELECT array_agg(DISTINCT username ORDER BY username)
      FROM poker_users 
      WHERE poker_users.poker_id = poker.id
        AND poker_users.left_at IS NULL
    )
    WHERE EXISTS (
      SELECT 1 FROM poker_users WHERE poker_users.poker_id = poker.id
    )
    """

    # Remove foreign key constraint and drop poker_users table
    drop constraint(:poker_users, :poker_users_poker_id_fkey)
    drop table(:poker_users)
  end

  def down do
    # Recreate poker_users table
    create table(:poker_users) do
      add :username, :string, null: false
      add :joined_at, :utc_datetime, null: false
      add :left_at, :utc_datetime
      add :muted, :boolean, default: false, null: false
      add :poker_id, references(:poker, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:poker_users, [:poker_id])

    create unique_index(:poker_users, [:poker_id, :username],
             name: :poker_users_poker_id_username_unique
           )

    # Migrate data back from usernames array to poker_users
    execute """
    INSERT INTO poker_users (username, joined_at, poker_id, inserted_at, updated_at)
    SELECT 
      unnest(usernames) as username,
      now() as joined_at,
      id as poker_id,
      now() as inserted_at,
      now() as updated_at
    FROM poker 
    WHERE usernames IS NOT NULL AND array_length(usernames, 1) > 0
    """

    # Remove usernames field from poker
    alter table(:poker) do
      remove :usernames
    end
  end
end
