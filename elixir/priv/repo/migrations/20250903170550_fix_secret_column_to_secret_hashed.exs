defmodule PlanningPoker.Repo.Migrations.FixSecretColumnToSecretHashed do
  use Ecto.Migration

  def change do
    # Add citext extension if not exists
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    # Rename secret column to secret_hashed
    rename table(:poker), :secret, to: :secret_hashed

    # Change moderator_email to citext
    alter table(:poker) do
      modify :moderator_email, :citext
    end
  end
end
