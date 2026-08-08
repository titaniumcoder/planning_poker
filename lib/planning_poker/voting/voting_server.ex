defmodule PlanningPoker.Voting.VotingServer do
  use GenServer
  require Logger

  @voting_timeout 30_000

  defstruct [
    :poker_id,
    :participants,
    :votes,
    :timer_ref,
    :status,
    :start_time
  ]

  @doc """
  Starts a VotingServer for the given poker session ID.
  """
  def start_link(poker_id) do
    GenServer.start_link(__MODULE__, poker_id, name: global_name(poker_id))
  end

  @doc """
  Starts a voting session with the given participants.
  """
  def start_voting_session(poker_id, participants) do
    with_server(poker_id, fn pid ->
      GenServer.call(pid, {:start_voting_session, participants})
    end)
  end

  @doc """
  Submits a vote for a user.
  """
  def submit_vote(poker_id, user_name, vote) do
    with_server(poker_id, fn pid ->
      GenServer.call(pid, {:submit_vote, user_name, vote})
    end)
  end

  @doc """
  Cancels the current voting session.
  """
  def cancel_voting(poker_id) do
    with_server(poker_id, fn pid ->
      GenServer.call(pid, :cancel_voting)
    end)
  end

  @doc """
  Gets the current voting state.
  """
  def get_voting_state(poker_id) do
    with_server(poker_id, fn pid ->
      GenServer.call(pid, :get_voting_state)
    end)
  end

  @doc """
  Gets the remaining voting time in seconds.
  """
  def get_remaining_time(poker_id) do
    with_server(poker_id, fn pid ->
      GenServer.call(pid, :get_remaining_time)
    end)
  end

  ## Server Callbacks

  @impl true
  def init(poker_id) do
    Logger.info("Starting VotingServer for poker #{poker_id}")

    {:ok,
     %__MODULE__{
       poker_id: poker_id,
       status: :idle
     }}
  end

  @impl true
  def handle_call({:start_voting_session, participants}, _from, state) do
    case state.status do
      :idle ->
        if participants != [] do
          start_time = System.system_time(:millisecond)
          timer_ref = Process.send_after(self(), :voting_timeout, @voting_timeout)

          new_state = %{
            state
            | participants: participants,
              votes: %{},
              timer_ref: timer_ref,
              status: :voting,
              start_time: start_time
          }

          broadcast_voting_started(state.poker_id)
          {:reply, {:ok, new_state}, new_state}
        else
          {:reply, {:error, :no_participants}, state}
        end

      _ ->
        {:reply, {:error, :voting_in_progress}, state}
    end
  end

  @impl true
  def handle_call({:submit_vote, user_name, vote}, _from, state) do
    case state.status do
      :voting ->
        handle_vote_submission(state, user_name, vote)

      _ ->
        {:reply, {:error, :no_voting_in_progress}, state}
    end
  end

  @impl true
  def handle_call(:cancel_voting, _from, state) do
    case state.status do
      :voting ->
        new_state = end_voting(state, :cancelled)
        {:reply, :ok, new_state}

      _ ->
        {:reply, {:error, :no_voting_in_progress}, state}
    end
  end

  @impl true
  def handle_call(:get_voting_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:get_remaining_time, _from, state) do
    case state.status do
      :voting ->
        if state.start_time do
          elapsed = System.system_time(:millisecond) - state.start_time
          remaining = max(0, div(@voting_timeout - elapsed, 1000))
          {:reply, {:ok, remaining}, state}
        else
          {:reply, {:ok, 30}, state}
        end

      _ ->
        {:reply, {:error, :no_voting_in_progress}, state}
    end
  end

  @impl true
  def handle_info(:voting_timeout, state) do
    case state.status do
      :voting ->
        new_state = end_voting(state, :timeout)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("VotingServer for poker #{state.poker_id} terminating: #{inspect(reason)}")

    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    :ok
  end

  ## Private Functions

  defp handle_vote_submission(state, user_name, vote) do
    if user_name in state.participants do
      process_valid_vote(state, user_name, vote)
    else
      {:reply, {:error, :not_participant}, state}
    end
  end

  defp process_valid_vote(state, user_name, vote) do
    new_votes = Map.put(state.votes, user_name, vote)
    new_state = %{state | votes: new_votes}

    broadcast_vote_submitted(state.poker_id, user_name, vote)

    if all_votes_submitted?(state.participants, new_votes) do
      {:reply, :ok, end_voting(new_state, :completed)}
    else
      {:reply, :ok, new_state}
    end
  end

  defp global_name(poker_id) do
    {:global, {:voting_server, poker_id}}
  end

  defp with_server(poker_id, callback) do
    case :global.whereis_name({:voting_server, poker_id}) do
      :undefined ->
        {:error, :server_not_found}

      pid ->
        callback.(pid)
    end
  end

  defp all_votes_submitted?(participants, votes) do
    length(participants) == map_size(votes)
  end

  defp end_voting(state, result_type) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    broadcast_voting_ended(state.poker_id, result_type, state.votes)

    %{state | participants: nil, votes: nil, timer_ref: nil, status: :idle, start_time: nil}
  end

  defp broadcast_voting_started(poker_id) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      "poker:#{poker_id}",
      {:voting_started}
    )
  end

  defp broadcast_vote_submitted(poker_id, user_name, vote) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      "poker:#{poker_id}",
      {:vote_submitted, user_name, vote}
    )
  end

  defp broadcast_voting_ended(poker_id, result_type, votes) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      "poker:#{poker_id}",
      {:voting_ended, result_type, votes}
    )
  end
end
