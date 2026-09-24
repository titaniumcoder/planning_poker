defmodule PlanningPoker.UserTracking.UserTrackingServer do
  @moduledoc """
  GenServer that tracks users for a poker session.
  Manages online/offline state, muted status, and syncs with database.
  """

  use GenServer
  require Logger

  alias PlanningPoker.Poker

  defstruct [
    :poker_id,
    users: %{},
    online_pids: %{}
  ]

  # Client API

  def start_link(poker_id) do
    GenServer.start_link(__MODULE__, poker_id, name: via_tuple(poker_id))
  end

  def join_user(poker_id, username) do
    safe_call(poker_id, {:join_user, username})
  end

  def mark_user_online(poker_id, username, pid) do
    safe_call(poker_id, {:mark_online, username, pid})
  end

  def mark_user_offline(poker_id, username, pid) do
    safe_call(poker_id, {:mark_offline, username, pid})
  end

  def toggle_mute_user(poker_id, username) do
    safe_call(poker_id, {:toggle_mute, username})
  end

  def get_users(poker_id) do
    safe_call(poker_id, :get_users)
  end

  def get_online_users(poker_id) do
    safe_call(poker_id, :get_online_users)
  end

  def get_unmuted_online_users(poker_id) do
    safe_call(poker_id, :get_unmuted_online_users)
  end

  def username_available?(poker_id, username) do
    safe_call(poker_id, {:username_available, username})
  end

  # Private helper to safely call GenServer
  defp safe_call(poker_id, message) do
    case GenServer.whereis(via_tuple(poker_id)) do
      nil ->
        {:error, :server_not_available}

      _pid ->
        try do
          GenServer.call(via_tuple(poker_id), message)
        catch
          :exit, {:noproc, _} -> {:error, :server_not_available}
        end
    end
  end

  # Server Callbacks

  @impl true
  def init(poker_id) do
    # Load existing users from database
    case Poker.get_poker(poker_id) do
      nil ->
        {:stop, :poker_not_found}

      poker ->
        # Initialize all registered users as offline
        users =
          (poker.usernames || [])
          |> Enum.map(fn username ->
            {username,
             %{
               username: username,
               # All start as offline after restart
               online: false,
               # Reset mute status after restart
               muted: false,
               joined_at: System.system_time(:second)
             }}
          end)
          |> Enum.into(%{})

        state = %__MODULE__{
          poker_id: poker_id,
          users: users,
          online_pids: %{}
        }

        Logger.info(
          "Started user tracking for poker #{poker_id} with #{map_size(users)} existing users (all offline after restart)"
        )

        {:ok, state}
    end
  end

  @impl true
  def handle_call({:join_user, username}, _from, state) do
    username = String.trim(username)

    if Map.has_key?(state.users, username) do
      {:reply, {:error, :username_taken}, state}
    else
      process_new_user_join(state, username)
    end
  end

  @impl true
  def handle_call({:mark_online, username, pid}, _from, state) do
    case Map.get(state.users, username) do
      nil ->
        {:reply, {:error, :user_not_found}, state}

      user_data ->
        # Monitor the process
        Process.monitor(pid)

        updated_user = %{user_data | online: true}
        updated_users = Map.put(state.users, username, updated_user)
        updated_pids = Map.put(state.online_pids, pid, username)

        new_state = %{state | users: updated_users, online_pids: updated_pids}

        # Only broadcast if the user's online status actually changed
        if !user_data.online do
          broadcast_user_update(new_state, {:user_came_online, updated_user})
        end

        {:reply, {:ok, updated_user}, new_state}
    end
  end

  @impl true
  def handle_call({:mark_offline, username, pid}, _from, state) do
    case Map.get(state.users, username) do
      nil ->
        {:reply, {:error, :user_not_found}, state}

      user_data ->
        updated_user = %{user_data | online: false}
        updated_users = Map.put(state.users, username, updated_user)
        updated_pids = Map.delete(state.online_pids, pid)

        new_state = %{state | users: updated_users, online_pids: updated_pids}

        broadcast_user_update(new_state, {:user_went_offline, updated_user})

        {:reply, {:ok, updated_user}, new_state}
    end
  end

  @impl true
  def handle_call({:toggle_mute, username}, _from, state) do
    case Map.get(state.users, username) do
      nil ->
        {:reply, {:error, :user_not_found}, state}

      user_data ->
        updated_user = %{user_data | muted: !user_data.muted}
        updated_users = Map.put(state.users, username, updated_user)

        new_state = %{state | users: updated_users}

        broadcast_user_update(new_state, {:user_mute_toggled, updated_user})

        {:reply, {:ok, updated_user}, new_state}
    end
  end

  @impl true
  def handle_call(:get_users, _from, state) do
    users = Map.values(state.users)
    {:reply, users, state}
  end

  @impl true
  def handle_call(:get_online_users, _from, state) do
    online_users =
      state.users
      |> Map.values()
      |> Enum.filter(& &1.online)

    {:reply, online_users, state}
  end

  @impl true
  def handle_call(:get_unmuted_online_users, _from, state) do
    unmuted_online_users =
      state.users
      |> Map.values()
      |> Enum.filter(&(&1.online and not &1.muted))
      |> Enum.map(& &1.username)

    {:reply, unmuted_online_users, state}
  end

  @impl true
  def handle_call({:username_available, username}, _from, state) do
    available = not Map.has_key?(state.users, username)
    {:reply, available, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Process went down, mark user as offline
    case Map.get(state.online_pids, pid) do
      nil ->
        {:noreply, state}

      username ->
        case Map.get(state.users, username) do
          nil ->
            {:noreply, state}

          user_data ->
            updated_user = %{user_data | online: false}
            updated_users = Map.put(state.users, username, updated_user)
            updated_pids = Map.delete(state.online_pids, pid)

            new_state = %{state | users: updated_users, online_pids: updated_pids}

            broadcast_user_update(new_state, {:user_went_offline, updated_user})

            {:noreply, new_state}
        end
    end
  end

  # Private functions

  defp process_new_user_join(state, username) do
    case Poker.get_poker(state.poker_id) do
      nil ->
        {:reply, {:error, :poker_not_found}, state}

      poker ->
        add_user_to_poker(state, poker, username)
    end
  end

  defp add_user_to_poker(state, poker, username) do
    updated_usernames = [username | poker.usernames || []]

    case Poker.update_poker(poker, %{usernames: updated_usernames}) do
      {:ok, _updated_poker} ->
        create_user_session(state, username)

      error ->
        {:reply, error, state}
    end
  end

  defp create_user_session(state, username) do
    user_data = %{
      username: username,
      online: false,
      muted: false,
      joined_at: System.system_time(:second)
    }

    updated_users = Map.put(state.users, username, user_data)
    new_state = %{state | users: updated_users}

    # Generate session token
    token = Poker.generate_user_token(state.poker_id, username)

    broadcast_user_update(new_state, {:user_joined, user_data})

    {:reply, {:ok, token}, new_state}
  end

  defp via_tuple(poker_id) do
    {:via, Registry, {PlanningPoker.Registry, {:user_tracking, poker_id}}}
  end

  defp broadcast_user_update(state, message) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      "poker:#{state.poker_id}",
      message
    )
  end
end
