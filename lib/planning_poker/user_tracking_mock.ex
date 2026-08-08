defmodule PlanningPoker.UserTrackingMock do
  @moduledoc """
  Mock implementation of UserTracking for tests.
  """

  @behaviour PlanningPoker.UserTrackingBehaviour

  # Table names for shared state across processes
  @online_users_table :test_online_users
  @muted_users_table :test_muted_users

  @impl PlanningPoker.UserTrackingBehaviour
  def stop_user_tracking(_poker_id) do
    # Clean up ETS tables or perform any necessary cleanup
    :ok
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def start_user_tracking(_poker_id) do
    # Ensure ETS tables exist for tests
    unless :ets.whereis(@online_users_table) != :undefined do
      :ets.new(@online_users_table, [:public, :named_table])
    end

    unless :ets.whereis(@muted_users_table) != :undefined do
      :ets.new(@muted_users_table, [:public, :named_table])
    end

    :ok
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def join_user(poker_id, username) do
    case PlanningPoker.Poker.get_poker(poker_id) do
      nil ->
        {:error, :poker_not_found}

      poker ->
        process_user_join(poker, username)
    end
  end

  defp process_user_join(poker, username) do
    if username in (poker.usernames || []) do
      {:error, :username_taken}
    else
      add_username_to_poker(poker, username)
    end
  end

  defp add_username_to_poker(poker, username) do
    updated_usernames = [username | poker.usernames || []]

    case PlanningPoker.Poker.update_poker(poker, %{usernames: updated_usernames}) do
      {:ok, _updated_poker} ->
        token = Base.encode64(:crypto.strong_rand_bytes(16))
        {:ok, token}

      error ->
        error
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def mark_user_online(poker_id, username, _pid) do
    # Check if user exists in the poker session
    case PlanningPoker.Poker.get_poker(poker_id) do
      nil ->
        {:error, :poker_not_found}

      poker ->
        if username in (poker.usernames || []) do
          # Track online users in ETS table
          safe_insert(@online_users_table, {poker_id, username}, true)
          {:ok, %{username: username, online: true}}
        else
          {:error, :user_not_found}
        end
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def mark_user_offline(poker_id, username, _pid) do
    # Track online users in ETS table. The table may already be gone when
    # the LiveView terminates (its owner process died), so guard the access.
    safe_insert(@online_users_table, {poker_id, username}, false)
    {:ok, %{username: username, online: false}}
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def toggle_mute_user(poker_id, username) do
    # Get current mute status
    current_muted =
      case safe_lookup(@muted_users_table, {poker_id, username}) do
        [{{^poker_id, ^username}, muted}] -> muted
        [] -> false
      end

    new_muted = !current_muted
    safe_insert(@muted_users_table, {poker_id, username}, new_muted)

    {:ok, %{username: username, muted: new_muted}}
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def get_users(poker_id) do
    case PlanningPoker.Poker.get_poker(poker_id) do
      nil -> []
      poker -> build_user_list(poker, poker_id)
    end
  end

  defp build_user_list(poker, poker_id) do
    (poker.usernames || [])
    |> Enum.map(&build_user_data(&1, poker_id))
  end

  defp build_user_data(username, poker_id) do
    online = get_online_status(poker_id, username)
    muted = get_muted_status(poker_id, username)

    %{
      username: username,
      online: online,
      muted: muted,
      joined_at: System.system_time(:second)
    }
  end

  defp get_online_status(poker_id, username) do
    case safe_lookup(@online_users_table, {poker_id, username}) do
      [{{^poker_id, ^username}, online_status}] -> online_status
      [] -> false
    end
  end

  defp get_muted_status(poker_id, username) do
    case safe_lookup(@muted_users_table, {poker_id, username}) do
      [{{^poker_id, ^username}, muted_status}] -> muted_status
      [] -> false
    end
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def get_online_users(poker_id) do
    get_users(poker_id)
    |> Enum.filter(& &1.online)
    |> Enum.map(& &1.username)
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def get_unmuted_online_users(poker_id) do
    get_users(poker_id)
    |> Enum.filter(&(&1.online && !&1.muted))
    |> Enum.map(& &1.username)
  end

  @impl PlanningPoker.UserTrackingBehaviour
  def username_available?(_poker_id, _username) do
    true
  end

  # ETS tables created in tests are owned by the process that created them
  # and disappear when that process exits. All access must therefore be
  # guarded so that late callbacks (e.g. LiveView terminate) never crash.

  defp safe_insert(table, key, value) do
    if :ets.whereis(table) != :undefined do
      :ets.insert(table, {key, value})
    end

    :ok
  end

  defp safe_lookup(table, key) do
    if :ets.whereis(table) != :undefined do
      :ets.lookup(table, key)
    else
      []
    end
  end
end
