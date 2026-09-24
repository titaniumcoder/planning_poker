defmodule PlanningPoker.UserTracking.UserTrackingSupervisor do
  @moduledoc """
  Supervisor for UserTracking servers, one per poker session.
  """

  use DynamicSupervisor

  alias PlanningPoker.UserTracking.UserTrackingServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a UserTracking server for a poker session.
  """
  def start_user_tracking(poker_id) do
    child_spec = %{
      id: "user_tracking_#{poker_id}",
      start: {UserTrackingServer, :start_link, [poker_id]},
      restart: :permanent,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  @doc """
  Stops the UserTracking server for a poker session.
  """
  def stop_user_tracking(poker_id) do
    case Registry.lookup(PlanningPoker.Registry, {:user_tracking, poker_id}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok

      [] ->
        :ok
    end
  end
end
