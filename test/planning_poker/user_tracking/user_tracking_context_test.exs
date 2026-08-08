defmodule PlanningPoker.UserTrackingContextTest do
  use PlanningPoker.DataCase

  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker
  alias PlanningPoker.UserTracking.UserTrackingServer
  alias PlanningPoker.UserTracking.UserTrackingSupervisor
  alias PlanningPoker.UserTrackingContext

  setup do
    poker = poker_fixture()
    %{poker: poker}
  end

  test "join_user/2 auto-starts the tracking server", %{poker: poker} do
    assert {:ok, token} = UserTrackingContext.join_user(poker.id, "alice")
    assert is_binary(token)
    assert "alice" in Poker.get_poker(poker.id).usernames
  end

  test "mark_user_online/3 auto-starts the tracking server", %{poker: poker} do
    {:ok, _token} = UserTrackingContext.join_user(poker.id, "alice")

    assert {:ok, %{username: "alice", online: true}} =
             UserTrackingContext.mark_user_online(poker.id, "alice", self())
  end

  test "mark_user_offline/3 returns :already_offline when no server is running", %{
    poker: poker
  } do
    assert {:ok, :already_offline} =
             UserTrackingContext.mark_user_offline(poker.id, "alice", self())
  end

  test "mark_user_offline/3 marks a tracked user offline", %{poker: poker} do
    {:ok, _token} = UserTrackingContext.join_user(poker.id, "alice")
    {:ok, _user} = UserTrackingContext.mark_user_online(poker.id, "alice", self())

    assert {:ok, %{username: "alice", online: false}} =
             UserTrackingContext.mark_user_offline(poker.id, "alice", self())
  end

  test "toggle_mute_user/2 errors when no server is running", %{poker: poker} do
    assert {:error, :server_not_available} =
             UserTrackingContext.toggle_mute_user(poker.id, "alice")
  end

  test "toggle_mute_user/2 toggles a tracked user", %{poker: poker} do
    {:ok, _token} = UserTrackingContext.join_user(poker.id, "alice")

    assert {:ok, %{username: "alice", muted: true}} =
             UserTrackingContext.toggle_mute_user(poker.id, "alice")
  end

  test "get_users/1 returns an empty list when no server is running", %{poker: poker} do
    assert [] = UserTrackingContext.get_users(poker.id)
  end

  test "get_online_users/1 returns an empty list when no server is running", %{poker: poker} do
    assert [] = UserTrackingContext.get_online_users(poker.id)
  end

  test "get_unmuted_online_users/1 returns an empty list when no server is running", %{
    poker: poker
  } do
    assert [] = UserTrackingContext.get_unmuted_online_users(poker.id)
  end

  test "username_available?/2 assumes available when no server is running", %{poker: poker} do
    assert UserTrackingContext.username_available?(poker.id, "alice")
  end

  test "start_user_tracking/1 is idempotent and stop_user_tracking/1 stops the server", %{
    poker: poker
  } do
    assert :ok = UserTrackingContext.start_user_tracking(poker.id)
    assert :ok = UserTrackingContext.start_user_tracking(poker.id)

    assert {:ok, _token} = UserTrackingServer.join_user(poker.id, "alice")

    assert :ok = UserTrackingContext.stop_user_tracking(poker.id)
    assert {:error, :server_not_available} = UserTrackingServer.get_users(poker.id)

    # Stopping again is a no-op
    assert :ok = UserTrackingContext.stop_user_tracking(poker.id)
  end

  test "stop_user_tracking/1 is a no-op when no server is running", %{poker: poker} do
    assert :ok = UserTrackingSupervisor.stop_user_tracking(poker.id)
  end
end
