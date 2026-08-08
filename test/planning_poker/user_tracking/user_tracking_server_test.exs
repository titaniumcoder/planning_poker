defmodule PlanningPoker.UserTracking.UserTrackingServerTest do
  use PlanningPoker.DataCase

  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker
  alias PlanningPoker.UserTracking.UserTrackingServer
  alias PlanningPoker.UserTracking.UserTrackingSupervisor

  setup do
    poker = poker_fixture()
    :ok = UserTrackingSupervisor.start_user_tracking(poker.id)
    Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker.id}")

    %{poker: poker}
  end

  describe "join_user/2" do
    test "adds the user to the poker and returns a token", %{poker: poker} do
      assert {:ok, token} = UserTrackingServer.join_user(poker.id, "alice")
      assert is_binary(token)

      assert_receive {:user_joined, %{username: "alice", online: false, muted: false}}
      assert "alice" in Poker.get_poker(poker.id).usernames
    end

    test "trims whitespace from the username", %{poker: poker} do
      assert {:ok, _token} = UserTrackingServer.join_user(poker.id, "  alice  ")
      assert "alice" in Poker.get_poker(poker.id).usernames
    end

    test "rejects an already taken username", %{poker: poker} do
      assert {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")
      assert {:error, :username_taken} = UserTrackingServer.join_user(poker.id, "alice")
    end
  end

  describe "online/offline tracking" do
    setup %{poker: poker} do
      {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")
      %{poker: poker}
    end

    test "marks a user online and broadcasts the change", %{poker: poker} do
      assert {:ok, %{username: "alice", online: true}} =
               UserTrackingServer.mark_user_online(poker.id, "alice", self())

      assert_receive {:user_came_online, %{username: "alice", online: true}}

      assert [%{username: "alice", online: true}] =
               UserTrackingServer.get_online_users(poker.id)
    end

    test "does not broadcast again when the user is already online", %{poker: poker} do
      {:ok, _user} = UserTrackingServer.mark_user_online(poker.id, "alice", self())
      assert_receive {:user_came_online, _}

      {:ok, _user} = UserTrackingServer.mark_user_online(poker.id, "alice", self())
      refute_receive {:user_came_online, _}
    end

    test "returns an error for unknown users", %{poker: poker} do
      assert {:error, :user_not_found} =
               UserTrackingServer.mark_user_online(poker.id, "ghost", self())

      assert {:error, :user_not_found} =
               UserTrackingServer.mark_user_offline(poker.id, "ghost", self())

      assert {:error, :user_not_found} = UserTrackingServer.toggle_mute_user(poker.id, "ghost")
    end

    test "marks a user offline and broadcasts the change", %{poker: poker} do
      {:ok, _user} = UserTrackingServer.mark_user_online(poker.id, "alice", self())
      assert_receive {:user_came_online, _}

      assert {:ok, %{username: "alice", online: false}} =
               UserTrackingServer.mark_user_offline(poker.id, "alice", self())

      assert_receive {:user_went_offline, %{username: "alice", online: false}}
      assert [] = UserTrackingServer.get_online_users(poker.id)
    end

    test "marks a user offline when their process dies", %{poker: poker} do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, _user} = UserTrackingServer.mark_user_online(poker.id, "alice", pid)
      assert_receive {:user_came_online, _}

      Process.exit(pid, :kill)

      assert_receive {:user_went_offline, %{username: "alice", online: false}}, 1000
    end
  end

  describe "mute tracking" do
    setup %{poker: poker} do
      {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")
      %{poker: poker}
    end

    test "toggles mute status and broadcasts the change", %{poker: poker} do
      assert {:ok, %{username: "alice", muted: true}} =
               UserTrackingServer.toggle_mute_user(poker.id, "alice")

      assert_receive {:user_mute_toggled, %{username: "alice", muted: true}}

      assert {:ok, %{username: "alice", muted: false}} =
               UserTrackingServer.toggle_mute_user(poker.id, "alice")

      assert_receive {:user_mute_toggled, %{username: "alice", muted: false}}
    end

    test "muted online users are excluded from unmuted online users", %{poker: poker} do
      {:ok, _user} = UserTrackingServer.mark_user_online(poker.id, "alice", self())

      assert ["alice"] = UserTrackingServer.get_unmuted_online_users(poker.id)

      {:ok, _user} = UserTrackingServer.toggle_mute_user(poker.id, "alice")
      assert [] = UserTrackingServer.get_unmuted_online_users(poker.id)
    end
  end

  describe "queries" do
    test "get_users/1 returns all registered users", %{poker: poker} do
      {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")
      {:ok, _token} = UserTrackingServer.join_user(poker.id, "bob")

      users = UserTrackingServer.get_users(poker.id)
      assert length(users) == 2
      assert Enum.map(users, & &1.username) |> Enum.sort() == ["alice", "bob"]
    end

    test "username_available?/2 reflects taken usernames", %{poker: poker} do
      assert UserTrackingServer.username_available?(poker.id, "alice")
      {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")
      refute UserTrackingServer.username_available?(poker.id, "alice")
    end
  end

  describe "server lifecycle" do
    test "fails to start for an unknown poker" do
      Process.flag(:trap_exit, true)

      assert {:error, :poker_not_found} =
               UserTrackingServer.start_link(Ecto.UUID.generate())
    end

    test "returns server_not_available when no server is running" do
      poker_id = Ecto.UUID.generate()

      assert {:error, :server_not_available} = UserTrackingServer.join_user(poker_id, "alice")
      assert {:error, :server_not_available} = UserTrackingServer.get_users(poker_id)
    end

    test "loads existing users as offline when restarted", %{poker: poker} do
      {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")
      {:ok, _user} = UserTrackingServer.mark_user_online(poker.id, "alice", self())

      :ok = UserTrackingSupervisor.stop_user_tracking(poker.id)
      :ok = UserTrackingSupervisor.start_user_tracking(poker.id)

      assert [%{username: "alice", online: false, muted: false}] =
               UserTrackingServer.get_users(poker.id)
    end
  end
end
