defmodule PlanningPoker.Voting.VotingServerTest do
  use ExUnit.Case, async: false

  alias PlanningPoker.PubSub
  alias PlanningPoker.Voting.VotingServer
  alias PlanningPoker.Voting.VotingSupervisor

  setup do
    poker_id = "test-poker-#{:rand.uniform(1000)}"
    {:ok, _pid} = VotingSupervisor.start_voting(poker_id)
    Phoenix.PubSub.subscribe(PubSub, "poker:#{poker_id}")

    %{poker_id: poker_id}
  end

  describe "voting session lifecycle" do
    test "starts voting session with participants", %{poker_id: poker_id} do
      participants = ["alice", "bob", "charlie"]

      assert {:ok, _state} = VotingServer.start_voting_session(poker_id, participants)
      assert_receive {:voting_started}

      {:ok, state} = VotingServer.get_voting_state(poker_id)
      assert state.status == :voting
      assert state.participants == participants
      assert state.votes == %{}
    end

    test "rejects starting voting when already in progress", %{poker_id: poker_id} do
      participants = ["alice", "bob"]

      assert {:ok, _state} = VotingServer.start_voting_session(poker_id, participants)

      assert {:error, :voting_in_progress} =
               VotingServer.start_voting_session(poker_id, ["charlie"])
    end

    test "rejects starting voting with no participants", %{poker_id: poker_id} do
      assert {:error, :no_participants} = VotingServer.start_voting_session(poker_id, [])
    end
  end

  describe "vote submission" do
    setup %{poker_id: poker_id} do
      participants = ["alice", "bob", "charlie"]
      {:ok, _state} = VotingServer.start_voting_session(poker_id, participants)
      clear_messages()

      %{participants: participants}
    end

    test "accepts valid vote from participant", %{poker_id: poker_id} do
      assert :ok = VotingServer.submit_vote(poker_id, "alice", "5")
      assert_receive {:vote_submitted, "alice", "5"}

      {:ok, state} = VotingServer.get_voting_state(poker_id)
      assert state.votes["alice"] == "5"
    end

    test "rejects vote from non-participant", %{poker_id: poker_id} do
      assert {:error, :not_participant} = VotingServer.submit_vote(poker_id, "david", "3")
      refute_receive {:vote_submitted, _, _}
    end

    test "completes voting when all participants vote", %{poker_id: poker_id} do
      VotingServer.submit_vote(poker_id, "alice", "5")
      VotingServer.submit_vote(poker_id, "bob", "8")
      VotingServer.submit_vote(poker_id, "charlie", "5")

      assert_receive {:vote_submitted, "alice", "5"}
      assert_receive {:vote_submitted, "bob", "8"}
      assert_receive {:vote_submitted, "charlie", "5"}

      assert_receive {:voting_ended, :completed,
                      %{"alice" => "5", "bob" => "8", "charlie" => "5"}}

      {:ok, state} = VotingServer.get_voting_state(poker_id)
      assert state.status == :idle
    end
  end

  describe "voting cancellation" do
    setup %{poker_id: poker_id} do
      participants = ["alice", "bob"]
      {:ok, _state} = VotingServer.start_voting_session(poker_id, participants)
      clear_messages()

      %{participants: participants}
    end

    test "cancels active voting session", %{poker_id: poker_id} do
      assert :ok = VotingServer.cancel_voting(poker_id)
      assert_receive {:voting_ended, :cancelled, %{}}

      {:ok, state} = VotingServer.get_voting_state(poker_id)
      assert state.status == :idle
    end

    test "rejects cancellation when no voting in progress", %{poker_id: poker_id} do
      VotingServer.cancel_voting(poker_id)
      clear_messages()

      assert {:error, :no_voting_in_progress} = VotingServer.cancel_voting(poker_id)
    end
  end

  describe "voting timeout" do
    test "times out after 30 seconds", %{poker_id: poker_id} do
      # We'll mock the timeout for faster testing
      participants = ["alice", "bob"]
      {:ok, _state} = VotingServer.start_voting_session(poker_id, participants)

      # Submit partial votes
      VotingServer.submit_vote(poker_id, "alice", "3")
      clear_messages()

      # Send timeout message directly to server
      pid = :global.whereis_name({:voting_server, poker_id})
      send(pid, :voting_timeout)

      assert_receive {:voting_ended, :timeout, %{"alice" => "3"}}, 1000

      {:ok, state} = VotingServer.get_voting_state(poker_id)
      assert state.status == :idle
    end
  end

  defp clear_messages do
    receive do
      _ -> clear_messages()
    after
      0 -> :ok
    end
  end
end
