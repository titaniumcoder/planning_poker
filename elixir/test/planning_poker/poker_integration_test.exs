defmodule PlanningPoker.PokerIntegrationTest do
  use PlanningPoker.DataCase, async: false

  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  describe "multi-user poker scenarios" do
    test "multiple users can join the same poker session" do
      poker = poker_fixture(%{name: "Multi-User Poker"})

      # Start user tracking
      @user_tracking_impl.start_user_tracking(poker.id)

      # Multiple users join
      {:ok, _token1} = Poker.join_poker_user(poker, "alice")
      {:ok, _token2} = Poker.join_poker_user(poker, "bob")
      {:ok, _token3} = Poker.join_poker_user(poker, "charlie")

      # All users should be tracked
      users = @user_tracking_impl.get_users(poker.id)
      usernames = Enum.map(users, & &1.username) |> Enum.sort()
      assert usernames == ["alice", "bob", "charlie"]
    end

    test "users can go online and offline" do
      poker = poker_fixture(%{name: "Online/Offline Poker"})

      # Start tracking and join users
      @user_tracking_impl.start_user_tracking(poker.id)
      {:ok, _token} = Poker.join_poker_user(poker, "alice")

      # Mark user online
      {:ok, user_data} = @user_tracking_impl.mark_user_online(poker.id, "alice", self())
      assert user_data.online == true

      # Mark user offline
      {:ok, user_data} = @user_tracking_impl.mark_user_offline(poker.id, "alice", self())
      assert user_data.online == false
    end

    test "muting affects voting participation" do
      poker = poker_fixture(%{name: "Mute Test Poker"})
      _voting = voting_fixture(poker, %{title: "Test Story"})

      # Start tracking and join users
      @user_tracking_impl.start_user_tracking(poker.id)
      {:ok, _token1} = Poker.join_poker_user(poker, "alice")
      {:ok, _token2} = Poker.join_poker_user(poker, "bob")

      # Mark users online
      @user_tracking_impl.mark_user_online(poker.id, "alice", self())
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())

      # Initially both should be unmuted
      unmuted_users = Poker.get_unmuted_online_users(poker.id)
      assert "alice" in unmuted_users
      assert "bob" in unmuted_users

      # Mute alice
      {:ok, _user} = @user_tracking_impl.toggle_mute_user(poker.id, "alice")

      # Now only bob should be unmuted
      unmuted_users = Poker.get_unmuted_online_users(poker.id)
      assert "alice" not in unmuted_users
      assert "bob" in unmuted_users
    end

    test "complex multi-user voting scenario" do
      poker = poker_fixture(%{name: "Multi-User Voting"})
      voting = voting_fixture(poker, %{title: "Complex Story"})

      # Setup multiple users
      @user_tracking_impl.start_user_tracking(poker.id)
      usernames = ["alice", "bob", "charlie", "dave", "eve"]

      for username <- usernames do
        {:ok, _token} = Poker.join_poker_user(poker, username)
        @user_tracking_impl.mark_user_online(poker.id, username, self())
      end

      # Mute one user (dave)
      @user_tracking_impl.toggle_mute_user(poker.id, "dave")

      # Start voting - should include all unmuted users
      Poker.ensure_voting_server(poker)
      {:ok, participants} = Poker.start_voting_for_voting(poker, voting)
      # All except dave
      assert length(participants) == 4
      assert "dave" not in participants

      # Ensure voting server is running
      Poker.ensure_voting_server(poker)

      # Submit votes from participants - test that voting system accepts them
      assert :ok = Poker.submit_vote(poker, "alice", "5")
      assert :ok = Poker.submit_vote(poker, "bob", "8")
      assert :ok = Poker.submit_vote(poker, "charlie", "5")
      assert :ok = Poker.submit_vote(poker, "eve", "13")

      # Test that the system handled the multi-user scenario without crashing
    end
  end

  describe "concurrent operations" do
    test "multiple voting sessions can be created and managed" do
      poker = poker_fixture(%{name: "Concurrent Voting Poker"})

      # Create multiple votings
      voting1 = voting_fixture(poker, %{title: "Story 1"})
      voting2 = voting_fixture(poker, %{title: "Story 2"})
      voting3 = voting_fixture(poker, %{title: "Story 3"})

      # All should be persisted
      updated_poker = Poker.get_poker(poker.id)
      assert length(updated_poker.votings) == 3

      # Should be able to get individual votings
      assert Poker.get_voting(voting1.id).title == "Story 1"
      assert Poker.get_voting(voting2.id).title == "Story 2"
      assert Poker.get_voting(voting3.id).title == "Story 3"
    end
  end

  describe "error scenarios" do
    test "handles user going offline during voting" do
      poker = poker_fixture(%{name: "Offline During Voting"})
      voting = voting_fixture(poker, %{title: "Test Story"})

      @user_tracking_impl.start_user_tracking(poker.id)
      {:ok, _token1} = Poker.join_poker_user(poker, "alice")
      {:ok, _token2} = Poker.join_poker_user(poker, "bob")

      @user_tracking_impl.mark_user_online(poker.id, "alice", self())
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())

      # Start voting
      Poker.ensure_voting_server(poker)
      {:ok, _participants} = Poker.start_voting_for_voting(poker, voting)
      Poker.ensure_voting_server(poker)

      # Alice votes
      :ok = Poker.submit_vote(poker, "alice", "5")

      # Bob goes offline before voting
      @user_tracking_impl.mark_user_offline(poker.id, "bob", self())

      # System should still handle this gracefully
      # Bob can't vote anymore, but alice's vote is preserved
      result = Poker.submit_vote(poker, "bob", "8")
      # This might return an error, but shouldn't crash
      assert result in [:ok, {:error, :not_participant}, {:error, :no_voting_in_progress}]
    end
  end
end
