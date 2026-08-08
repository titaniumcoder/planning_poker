defmodule PlanningPoker.Voting.VotingSupervisorTest do
  use ExUnit.Case, async: false

  alias PlanningPoker.Voting.VotingServer
  alias PlanningPoker.Voting.VotingSupervisor

  setup do
    poker_id = "supervisor-test-poker-#{System.unique_integer([:positive])}"
    %{poker_id: poker_id}
  end

  test "start_voting/1 starts a voting server", %{poker_id: poker_id} do
    assert {:ok, pid} = VotingSupervisor.start_voting(poker_id)
    assert is_pid(pid)
    assert Process.alive?(pid)

    VotingSupervisor.stop_voting(poker_id)
  end

  test "start_voting/1 is idempotent", %{poker_id: poker_id} do
    assert {:ok, pid} = VotingSupervisor.start_voting(poker_id)
    assert {:ok, ^pid} = VotingSupervisor.start_voting(poker_id)

    VotingSupervisor.stop_voting(poker_id)
  end

  test "stop_voting/1 terminates a running server", %{poker_id: poker_id} do
    {:ok, _pid} = VotingSupervisor.start_voting(poker_id)
    assert :ok = VotingSupervisor.stop_voting(poker_id)
    assert :undefined == :global.whereis_name({:voting_server, poker_id})
  end

  test "stop_voting/1 returns an error when no server is running", %{poker_id: poker_id} do
    assert {:error, :not_found} = VotingSupervisor.stop_voting(poker_id)
  end

  test "list_voting_sessions/0 lists running sessions", %{poker_id: poker_id} do
    {:ok, pid} = VotingSupervisor.start_voting(poker_id)

    sessions = VotingSupervisor.list_voting_sessions()
    assert {^poker_id, ^pid} = List.keyfind(sessions, poker_id, 0)

    VotingSupervisor.stop_voting(poker_id)

    sessions = VotingSupervisor.list_voting_sessions()
    refute List.keyfind(sessions, poker_id, 0)
  end

  test "voting servers are reachable through the VotingServer API", %{poker_id: poker_id} do
    {:ok, _pid} = VotingSupervisor.start_voting(poker_id)

    assert {:ok, %VotingServer{status: :idle}} = VotingServer.get_voting_state(poker_id)

    VotingSupervisor.stop_voting(poker_id)
  end
end
