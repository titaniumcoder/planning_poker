defmodule PlanningPoker.Voting.VotingSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a VotingServer for the given poker ID.
  """
  def start_voting(poker_id) do
    child_spec = %{
      id: PlanningPoker.Voting.VotingServer,
      start: {PlanningPoker.Voting.VotingServer, :start_link, [poker_id]},
      restart: :transient
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started VotingServer for poker #{poker_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("VotingServer for poker #{poker_id} already running")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start VotingServer for poker #{poker_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops the VotingServer for the given poker ID.
  """
  def stop_voting(poker_id) do
    case :global.whereis_name({:voting_server, poker_id}) do
      :undefined ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Lists all currently running voting sessions.
  """
  def list_voting_sessions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      case GenServer.call(pid, :get_voting_state) do
        {:ok, state} -> {state.poker_id, pid}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
