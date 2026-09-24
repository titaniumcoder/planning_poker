# Start the Registry for tests (if not already started)
case Registry.start_link(keys: :unique, name: PlanningPoker.Registry) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(PlanningPoker.Repo, :manual)
