defmodule PlanningPoker.PokerContextExtraTest do
  use PlanningPoker.DataCase

  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker
  alias PlanningPoker.Poker.Voting
  alias PlanningPoker.Voting.VotingSupervisor

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  describe "delete_poker/1" do
    test "deletes the poker and stops its voting server" do
      poker = poker_fixture()
      {:ok, _pid} = Poker.ensure_voting_server(poker)

      assert {:ok, _poker} = Poker.delete_poker(poker)
      assert Poker.get_poker(poker.id) == nil
      assert {:error, :not_found} = VotingSupervisor.stop_voting(poker.id)
    end

    test "cascades to votings" do
      poker = poker_fixture()
      voting = voting_fixture(poker)

      assert {:ok, _poker} = Poker.delete_poker(poker)
      assert Poker.get_voting(voting.id) == nil
    end
  end

  describe "user management" do
    test "leave_poker_user/2 broadcasts a user_left event" do
      poker = poker_fixture()
      Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker.id}")

      assert {:ok, %{username: "alice"}} = Poker.leave_poker_user(poker.id, "alice")
      assert_receive {:user_left, "alice"}
    end

    test "toggle_mute_poker_user/2 delegates to the user tracking implementation" do
      poker = poker_fixture()
      {:ok, _token} = Poker.join_poker_user(poker, "alice")

      assert {:ok, %{username: "alice", muted: true}} =
               Poker.toggle_mute_poker_user(poker.id, "alice")
    end

    test "get_online_poker_users/1, get_poker_users/1 and username_available?/2" do
      poker = poker_fixture()
      {:ok, _token} = Poker.join_poker_user(poker, "alice")

      @user_tracking_impl.start_user_tracking(poker.id)
      @user_tracking_impl.mark_user_online(poker.id, "alice", self())

      assert ["alice"] = Poker.get_online_poker_users(poker.id)
      assert [%{username: "alice"}] = Poker.get_poker_users(poker.id)
      # The mock implementation always reports usernames as available
      assert Poker.username_available?(poker.id, "bob")
    end

    test "join_poker_user/2 rejects duplicate usernames" do
      poker = poker_fixture()
      {:ok, _token} = Poker.join_poker_user(poker, "alice")
      assert {:error, :username_taken} = Poker.join_poker_user(poker, "alice")
    end
  end

  describe "session tokens" do
    test "generate_user_token/2 is deterministic" do
      poker = poker_fixture()
      token = Poker.generate_user_token(poker.id, "alice")
      assert token == Poker.generate_user_token(poker.id, "alice")
      assert token != Poker.generate_user_token(poker.id, "bob")
    end

    test "validate_user_token/3 accepts the generated token" do
      poker = poker_fixture()
      %{token: token} = join_poker_user_fixture(poker, "alice")
      assert Poker.validate_user_token(poker.id, "alice", token)
      refute Poker.validate_user_token(poker.id, "alice", "wrong-token-of-wrong-length")
    end

    test "validate_user_token/3 accepts 24 char test tokens when bypass is enabled" do
      poker = poker_fixture()
      test_token = Base.encode64(:crypto.strong_rand_bytes(16))
      assert String.length(test_token) == 24
      assert Poker.validate_user_token(poker.id, "anyone", test_token)
    end

    test "validate_user_session/3 verifies poker, membership and token" do
      poker = poker_fixture()

      assert {:error, :poker_not_found} =
               Poker.validate_user_session(Ecto.UUID.generate(), "alice", "token")

      assert {:error, :invalid_session} =
               Poker.validate_user_session(poker.id, "ghost", "token")

      %{token: token} = join_poker_user_fixture(poker, "alice")

      assert {:ok, %{username: "alice", poker_id: poker_id}} =
               Poker.validate_user_session(poker.id, "alice", token)

      assert poker_id == poker.id
    end
  end

  describe "change_poker/1" do
    test "returns a changeset reporting errors" do
      poker = poker_fixture()

      changeset = Poker.change_poker(poker, %{card_type: "invalid"})

      assert %{card_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "voting management" do
    test "get_voting/1 returns the voting or nil" do
      poker = poker_fixture()
      voting = voting_fixture(poker)

      assert %Voting{id: id} = Poker.get_voting(voting.id)
      assert id == voting.id
      assert Poker.get_voting(-1) == nil
    end

    test "get_poker_votings/1 returns votings ordered by position" do
      poker = poker_fixture()
      voting1 = voting_fixture(poker, %{title: "first"})
      voting2 = voting_fixture(poker, %{title: "second"})

      votings = Poker.get_poker_votings(poker.id)
      assert Enum.map(votings, & &1.id) == [voting1.id, voting2.id]
      assert Enum.map(votings, & &1.position) == [1, 2]
    end

    test "create_voting/2 assigns increasing positions and broadcasts" do
      poker = poker_fixture()
      Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker.id}")

      assert {:ok, voting1} = Poker.create_voting(poker, %{title: "first"})
      assert_receive {:voting_created, %Voting{id: id1}}
      assert id1 == voting1.id

      assert {:ok, voting2} = Poker.create_voting(poker, %{title: "second"})

      assert voting1.position == 1
      assert voting2.position == 2
    end

    test "create_voting/2 returns an error changeset for invalid attrs" do
      poker = poker_fixture()
      assert {:error, %Ecto.Changeset{}} = Poker.create_voting(poker, %{title: nil})
    end

    test "update_voting/2 updates and broadcasts" do
      poker = poker_fixture()
      voting = voting_fixture(poker)
      Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker.id}")

      assert {:ok, updated} = Poker.update_voting(voting, %{title: "new title"})
      assert updated.title == "new title"
      assert_receive {:voting_updated, %Voting{title: "new title"}}
    end

    test "delete_voting/1 deletes and broadcasts" do
      poker = poker_fixture()
      voting = voting_fixture(poker)
      Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker.id}")

      assert {:ok, _voting} = Poker.delete_voting(voting)
      assert_receive {:voting_deleted, _voting}
      assert Poker.get_voting(voting.id) == nil
    end

    test "set_voting_decision/2 and remove_voting_decision/1" do
      poker = poker_fixture()
      voting = voting_fixture(poker)

      assert {:ok, with_decision} = Poker.set_voting_decision(voting, "5")
      assert with_decision.decision == "5"

      assert {:ok, without_decision} = Poker.remove_voting_decision(with_decision)
      assert without_decision.decision == nil
    end

    test "start_voting_for_voting/2 errors without participants" do
      poker = poker_fixture()
      voting = voting_fixture(poker)

      assert {:error, :no_participants} = Poker.start_voting_for_voting(poker, voting)
    end

    test "start_voting_for_voting/2 starts with online unmuted participants" do
      poker = poker_fixture()
      voting = voting_fixture(poker)
      Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker.id}")

      {:ok, _token} = Poker.join_poker_user(poker, "alice")
      @user_tracking_impl.start_user_tracking(poker.id)
      @user_tracking_impl.mark_user_online(poker.id, "alice", self())

      {:ok, _pid} = Poker.ensure_voting_server(poker)

      assert {:ok, ["alice"]} = Poker.start_voting_for_voting(poker, voting)
      assert_receive {:voting_session_started, voting_id}
      assert voting_id == voting.id

      Poker.cancel_voting_session(poker)
    end

    test "voting server API without a running server" do
      poker = poker_fixture()

      assert {:error, :server_not_found} = Poker.submit_vote(poker, "alice", "5")
      assert {:error, :server_not_found} = Poker.cancel_voting_session(poker)
      assert {:error, :server_not_found} = Poker.get_voting_session_state(poker)
      assert {:error, :server_not_found} = Poker.get_voting_remaining_time(poker)
    end

    test "save_voting_result/4 ignores empty votes" do
      poker = poker_fixture()
      voting = voting_fixture(poker)

      assert {:ok, ^voting} = Poker.save_voting_result(voting, :completed, %{}, ["alice"])
    end

    test "save_voting_result/4 keeps an existing decision" do
      poker = poker_fixture()
      voting = voting_fixture(poker)
      {:ok, voting} = Poker.set_voting_decision(voting, "8")

      votes = %{"alice" => "5", "bob" => "5"}

      assert {:ok, updated} =
               Poker.save_voting_result(voting, :completed, votes, ["alice", "bob"])

      # The unanimous vote would suggest "5", but the existing decision wins
      assert updated.decision == "8"
    end
  end

  describe "ensure_voting_server/1" do
    test "starts the user tracking and voting servers" do
      poker = poker_fixture()
      assert {:ok, pid} = Poker.ensure_voting_server(poker)
      assert is_pid(pid)

      # Starting again returns the same server
      assert {:ok, ^pid} = Poker.ensure_voting_server(poker)

      Poker.stop_voting_server(poker)
    end
  end
end
