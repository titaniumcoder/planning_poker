defmodule PlanningPoker.PokerVotingTest do
  use PlanningPoker.DataCase

  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  describe "card management" do
    test "card_types/0 returns available card types" do
      assert Poker.card_types() == ["fibonacci", "t-shirt"]
    end

    test "card_options/1 returns correct options for fibonacci" do
      expected = ["?", "1", "2", "3", "5", "8", "13", "20", "40", "100"]
      assert Poker.card_options("fibonacci") == expected
    end

    test "card_options/1 returns correct options for t-shirt" do
      expected = ["?", "XS", "S", "M", "L", "XL", "XXL"]
      assert Poker.card_options("t-shirt") == expected
    end

    test "card_options/1 returns fibonacci for unknown card type" do
      expected = ["?", "1", "2", "3", "5", "8", "13", "20", "40", "100"]
      assert Poker.card_options("unknown") == expected
    end

    test "card_type_options/0 returns form options" do
      expected = [{"Fibonacci", "fibonacci"}, {"T-Shirt", "t-shirt"}]
      assert Poker.card_type_options() == expected
    end

    test "valid_card_type?/1 validates card types" do
      assert Poker.valid_card_type?("fibonacci")
      assert Poker.valid_card_type?("t-shirt")
      refute Poker.valid_card_type?("unknown")
      refute Poker.valid_card_type?(nil)
    end
  end

  describe "voting server management" do
    test "ensure_voting_server/1 starts voting server for open poker" do
      poker = poker_fixture(%{name: "Test Poker"})

      assert {:ok, _pid} = Poker.ensure_voting_server(poker)

      # Should be idempotent
      assert {:ok, _pid} = Poker.ensure_voting_server(poker)
    end

    test "ensure_voting_server/1 rejects closed poker" do
      poker = poker_fixture(%{name: "Test Poker"})
      {:ok, closed_poker} = Poker.close_poker(poker)

      assert {:error, :poker_closed} = Poker.ensure_voting_server(closed_poker)
    end
  end

  describe "get_unmuted_online_users/1" do
    test "returns only unmuted online users" do
      poker = poker_fixture(%{name: "Test Poker"})

      # Join users
      {:ok, _token1} = Poker.join_poker_user(poker, "alice")
      {:ok, _token2} = Poker.join_poker_user(poker, "bob")
      {:ok, _token3} = Poker.join_poker_user(poker, "charlie")

      # Start user tracking server (mock)
      @user_tracking_impl.start_user_tracking(poker.id)

      # Mark users as online (simulate LiveView connection)
      @user_tracking_impl.mark_user_online(poker.id, "alice", self())
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())
      @user_tracking_impl.mark_user_online(poker.id, "charlie", self())

      # Mute one user
      {:ok, _muted_user} = @user_tracking_impl.toggle_mute_user(poker.id, "charlie")

      # Mark one user as offline
      {:ok, _left_user} = @user_tracking_impl.mark_user_offline(poker.id, "bob", self())

      unmuted_users = Poker.get_unmuted_online_users(poker.id)
      assert unmuted_users == ["alice"]
    end
  end

  describe "voting result persistence" do
    test "save_voting_result/4 saves vote data to voting" do
      poker = poker_fixture(%{name: "Test Poker"})
      voting = voting_fixture(poker, %{title: "Test Story"})

      votes = %{"alice" => "5", "bob" => "8"}
      participants = ["alice", "bob"]

      assert {:ok, updated_voting} =
               Poker.save_voting_result(voting, :completed, votes, participants)

      assert length(updated_voting.votes) == 1

      vote_round = List.first(updated_voting.votes)

      assert Map.get(vote_round, "result") == "completed" or
               Map.get(vote_round, :result) == :completed

      assert Map.get(vote_round, "votes") == votes or Map.get(vote_round, :votes) == votes

      assert Map.get(vote_round, "participants") == participants or
               Map.get(vote_round, :participants) == participants
    end

    test "save_voting_result/4 sets automatic decision for unanimous non-? votes" do
      poker = poker_fixture(%{name: "Test Poker"})
      voting = voting_fixture(poker, %{title: "Test Story"})

      votes = %{"alice" => "5", "bob" => "5"}
      participants = ["alice", "bob"]

      assert {:ok, _updated_voting} =
               Poker.save_voting_result(voting, :completed, votes, participants)

      # Check that decision was automatically set
      updated_voting = Poker.get_voting(voting.id)
      assert updated_voting.decision == "5"
    end

    test "save_voting_result/4 does not set decision for mixed votes" do
      poker = poker_fixture(%{name: "Test Poker"})
      voting = voting_fixture(poker, %{title: "Test Story"})

      votes = %{"alice" => "5", "bob" => "8"}
      participants = ["alice", "bob"]

      assert {:ok, _updated_voting} =
               Poker.save_voting_result(voting, :completed, votes, participants)

      # Check that no decision was set
      updated_voting = Poker.get_voting(voting.id)
      assert is_nil(updated_voting.decision)
    end

    test "save_voting_result/4 does not set decision for ? votes" do
      poker = poker_fixture(%{name: "Test Poker"})
      voting = voting_fixture(poker, %{title: "Test Story"})

      votes = %{"alice" => "?", "bob" => "?"}
      participants = ["alice", "bob"]

      assert {:ok, _updated_voting} =
               Poker.save_voting_result(voting, :completed, votes, participants)

      # Check that no decision was set
      updated_voting = Poker.get_voting(voting.id)
      assert is_nil(updated_voting.decision)
    end
  end
end
