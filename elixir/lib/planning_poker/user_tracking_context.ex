defmodule PlanningPoker.UserTrackingContext do
  @moduledoc """
  Context module for user tracking that properly delegates to the supervisor and server.
  """

  @behaviour PlanningPoker.UserTrackingBehaviour

  alias PlanningPoker.UserTracking.{UserTrackingServer, UserTrackingSupervisor}

  @impl PlanningPoker.UserTrackingBehaviour
  def stop_user_tracking(poker_id) do
    UserTrackingSupervisor.stop_user_tracking(poker_id)
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def start_user_tracking(poker_id) do
    UserTrackingSupervisor.start_user_tracking(poker_id)
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def join_user(poker_id, username) do
    call_with_auto_start(poker_id, fn -> UserTrackingServer.join_user(poker_id, username) end)
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def mark_user_online(poker_id, username, pid) do
    call_with_auto_start(poker_id, fn ->
      UserTrackingServer.mark_user_online(poker_id, username, pid)
    end)
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def mark_user_offline(poker_id, username, pid) do
    case UserTrackingServer.mark_user_offline(poker_id, username, pid) do
      {:error, :server_not_available} ->
        # Server not running, user is already effectively offline
        {:ok, :already_offline}

      result ->
        result
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def toggle_mute_user(poker_id, username) do
    case UserTrackingServer.toggle_mute_user(poker_id, username) do
      {:error, :server_not_available} ->
        {:error, :server_not_available}

      result ->
        result
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def get_users(poker_id) do
    case UserTrackingServer.get_users(poker_id) do
      {:error, :server_not_available} -> []
      users when is_list(users) -> users
      error -> error
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def get_online_users(poker_id) do
    case UserTrackingServer.get_online_users(poker_id) do
      {:error, :server_not_available} -> []
      users when is_list(users) -> users
      error -> error
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def get_unmuted_online_users(poker_id) do
    case UserTrackingServer.get_unmuted_online_users(poker_id) do
      {:error, :server_not_available} -> []
      users when is_list(users) -> users
      error -> error
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def username_available?(poker_id, username) do
    case UserTrackingServer.username_available?(poker_id, username) do
      # Assume available if no server
      {:error, :server_not_available} -> true
      result when is_boolean(result) -> result
      # Default to available on other errors
      _error -> true
    end
  end

  # Private helper function
  # NOTE: This is technical debt - ideally the supervisor would handle
  # automatic server startup, but this is the easiest solution for now.
  defp call_with_auto_start(poker_id, fun) do
    case fun.() do
      {:error, :server_not_available} ->
        # Try to start the server and retry
        case start_user_tracking(poker_id) do
          :ok -> fun.()
          error -> error
        end

      result ->
        result
    end
  end
end
