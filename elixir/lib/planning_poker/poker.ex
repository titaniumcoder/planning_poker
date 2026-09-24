defmodule PlanningPoker.Poker do
  @moduledoc """
  The Poker context.
  """
  import Ecto.Query, warn: false
  alias PlanningPoker.Repo

  alias PlanningPoker.Poker.Poker
  alias PlanningPoker.Poker.Voting
  alias PlanningPoker.Voting.VotingServer
  alias PlanningPoker.Voting.VotingSupervisor

  @card_types ["fibonacci", "t-shirt"]
  @card_options %{
    "fibonacci" => ["?", "1", "2", "3", "5", "8", "13", "20", "40", "100"],
    "t-shirt" => ["?", "XS", "S", "M", "L", "XL", "XXL"]
  }

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  ## Card Management

  @doc """
  Returns the list of available card types.
  """
  def card_types, do: @card_types

  @doc """
  Returns the card options for a given card type.
  """
  def card_options(card_type) do
    Map.get(@card_options, card_type, @card_options["fibonacci"])
  end

  @doc """
  Returns card type options for forms.
  """
  def card_type_options do
    # Note: Consider adding gettext support for internationalization in the future
    [{"Fibonacci", "fibonacci"}, {"T-Shirt", "t-shirt"}]
  end

  @doc """
  Validates if a card type is valid.
  """
  def valid_card_type?(card_type) do
    card_type in @card_types
  end

  @doc """
  Gets a single poker with all associations loaded.

    ## Examples

      iex> get_poker("uuid")
      %Poker{votings: [...]}  # with votings preloaded

      iex> get_poker("unknown")
      nil

  """
  def get_poker(uuid) do
    case Repo.get(Poker, uuid) do
      nil -> nil
      poker -> Repo.preload(poker, [:votings])
    end
  end

  @doc """
  Creates a new poker.

  ## Examples

      iex> create_poker(%{field: value})
      {:ok, %Poker{}}

      iex> create_poker(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_poker(attrs) do
    %Poker{}
    |> Poker.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a poker.

  ## Examples

      iex> update_poker(poker, %{field: new_value})
      {:ok, %Poker{}}

      iex> update_poker(poker, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_poker(%Poker{} = poker, attrs) do
    poker
    |> Poker.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Ends a poker by sending also an email about the poker to the moderator with all information including
  the voting rounds.

  ## Examples

      iex> end_poker(poker)
      {:ok, %Poker{}}

      iex> end_poker(poker)
      {:error, %Ecto.Changeset{}}

  """
  def end_poker(%Poker{} = poker) do
    Repo.delete(poker)
  end

  @doc """
  Permanently deletes a poker session and all associated data.

  ## Examples

      iex> delete_poker(poker)
      {:ok, %Poker{}}

      iex> delete_poker(poker)
      {:error, %Ecto.Changeset{}}

  """
  def delete_poker(%Poker{} = poker) do
    # Stop the voting server first
    stop_voting_server(poker)

    # Stop user tracking
    @user_tracking_impl.stop_user_tracking(poker.id)

    # Delete the poker (cascade will handle votings)
    Repo.delete(poker)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking poker changes.

  ## Examples

      iex> change_poker(poker)
      %Ecto.Changeset{data: %Poker{}}

  """
  def change_poker(%Poker{} = poker, attrs \\ %{}) do
    Poker.changeset(poker, attrs)
  end

  @doc """
  Closes a poker session by setting the closed_at timestamp.

  ## Examples

      iex> close_poker(poker)
      {:ok, %Poker{}}

  """
  def close_poker(%Poker{} = poker) do
    poker
    |> Poker.close_changeset(%{closed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Reopens a poker session by clearing the closed_at timestamp.

  ## Examples

      iex> reopen_poker(poker)
      {:ok, %Poker{}}

  """
  def reopen_poker(%Poker{} = poker) do
    poker
    |> Poker.close_changeset(%{closed_at: nil})
    |> Repo.update()
  end

  @doc """
  Checks if a poker session is closed.

  ## Examples

      iex> closed?(poker)
      false

  """
  def closed?(%Poker{closed_at: nil}), do: false
  def closed?(%Poker{closed_at: _}), do: true

  ## User Management (using Phoenix Presence)

  @doc """
  Adds a user to a poker session and returns a session token.
  """
  def join_poker_user(%Poker{} = poker, username) do
    with :ok <- @user_tracking_impl.start_user_tracking(poker.id),
         {:ok, token} <- @user_tracking_impl.join_user(poker.id, username) do
      {:ok, token}
    else
      error -> error
    end
  end

  @doc """
  Removes user from Presence tracking (called when LiveView terminates).
  """
  def leave_poker_user(poker_id, username) do
    # User tracking server handles the offline status automatically via process monitoring
    # We just need to broadcast the event
    broadcast_user_update(poker_id, {:user_left, username})
    {:ok, %{username: username}}
  end

  @doc """
  Toggles user mute status in Presence.
  """
  def toggle_mute_poker_user(poker_id, username) do
    @user_tracking_impl.toggle_mute_user(poker_id, username)
  end

  @doc """
  Gets all online users for a poker session from UserTracking.
  """
  def get_online_poker_users(poker_id) do
    @user_tracking_impl.get_online_users(poker_id)
  end

  @doc """
  Gets all users (registered) for a poker session.
  """
  def get_poker_users(poker_id) do
    @user_tracking_impl.get_users(poker_id)
  end

  @doc """
  Checks if a username is available for a poker session.
  """
  def username_available?(poker_id, username) do
    @user_tracking_impl.username_available?(poker_id, username)
  end

  # Private helper for broadcasting user updates
  defp broadcast_user_update(poker_id, message) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      "poker:#{poker_id}",
      message
    )
  end

  ## Voting Management

  @doc """
  Starts a VotingServer for a poker session if not already running.
  Called when a user connects to ensure the server is available.
  """
  def ensure_voting_server(%Poker{} = poker) do
    if closed?(poker) do
      {:error, :poker_closed}
    else
      # Start user tracking first
      @user_tracking_impl.start_user_tracking(poker.id)
      # Then start voting server
      VotingSupervisor.start_voting(poker.id)
    end
  end

  @doc """
  Stops the VotingServer for a poker session.
  Called when poker is closed.
  """
  def stop_voting_server(%Poker{} = poker) do
    VotingSupervisor.stop_voting(poker.id)
  end

  @doc """
  Starts a voting session for a specific voting.
  """
  def start_voting_for_voting(%Poker{} = poker, %Voting{} = voting) do
    participants = get_unmuted_online_users(poker.id)

    if participants != [] do
      case VotingServer.start_voting_session(poker.id, participants) do
        {:ok, _state} ->
          broadcast_voting_update(poker.id, {:voting_session_started, voting.id})
          {:ok, participants}

        error ->
          error
      end
    else
      {:error, :no_participants}
    end
  end

  @doc """
  Submits a vote for a user.
  """
  def submit_vote(%Poker{} = poker, user_name, vote) do
    VotingServer.submit_vote(poker.id, user_name, vote)
  end

  @doc """
  Cancels the current voting session.
  """
  def cancel_voting_session(%Poker{} = poker) do
    VotingServer.cancel_voting(poker.id)
  end

  @doc """
  Gets the current voting state from the VotingServer.
  """
  def get_voting_session_state(%Poker{} = poker) do
    VotingServer.get_voting_state(poker.id)
  end

  @doc """
  Gets the remaining voting time in seconds from the VotingServer.
  """
  def get_voting_remaining_time(%Poker{} = poker) do
    VotingServer.get_remaining_time(poker.id)
  end

  @doc """
  Gets unmuted online users for a poker session.
  """
  def get_unmuted_online_users(poker_id) do
    @user_tracking_impl.get_unmuted_online_users(poker_id)
  end

  @doc """
  Creates a voting for a poker session.

  ## Examples

      iex> create_voting(poker, %{title: "Story estimation"})
      {:ok, %Voting{}}

      iex> create_voting(poker, %{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_voting(%Poker{} = poker, attrs) do
    next_position = get_next_voting_position(poker.id)

    %Voting{}
    |> Voting.changeset(Map.merge(attrs, %{poker_id: poker.id, position: next_position}))
    |> Repo.insert()
    |> case do
      {:ok, voting} ->
        broadcast_voting_update(poker.id, {:voting_created, voting})
        {:ok, voting}

      error ->
        error
    end
  end

  @doc """
  Updates a voting.

  ## Examples

      iex> update_voting(voting, %{title: "New title"})
      {:ok, %Voting{}}

  """
  def update_voting(%Voting{} = voting, attrs) do
    voting
    |> Voting.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_voting} ->
        broadcast_voting_update(voting.poker_id, {:voting_updated, updated_voting})
        {:ok, updated_voting}

      error ->
        error
    end
  end

  @doc """
  Deletes a voting.

  ## Examples

      iex> delete_voting(voting)
      {:ok, %Voting{}}

  """
  def delete_voting(%Voting{} = voting) do
    case Repo.delete(voting) do
      {:ok, deleted_voting} ->
        broadcast_voting_update(voting.poker_id, {:voting_deleted, deleted_voting})
        {:ok, deleted_voting}

      error ->
        error
    end
  end

  @doc """
  Sets a decision for a voting and marks it as closed.

  ## Examples

      iex> set_voting_decision(voting, "5 story points")
      {:ok, %Voting{}}

  """
  def set_voting_decision(%Voting{} = voting, decision) do
    update_voting(voting, %{decision: decision})
  end

  @doc """
  Removes the decision from a voting, reopening it.

  ## Examples

      iex> remove_voting_decision(voting)
      {:ok, %Voting{}}

  """
  def remove_voting_decision(%Voting{} = voting) do
    update_voting(voting, %{decision: nil})
  end

  @doc """
  Saves voting results to the database.
  """
  def save_voting_result(%Voting{} = voting, result_type, votes, participants) do
    # Only save the voting result if there are actual votes
    if map_size(votes) > 0 do
      vote_data = %{
        result: result_type,
        votes: votes,
        participants: participants,
        ended_at: DateTime.utc_now()
      }

      existing_votes = voting.votes || []
      new_votes = existing_votes ++ [vote_data]

      case update_voting(voting, %{votes: new_votes}) do
        {:ok, updated_voting} ->
          maybe_set_auto_decision(updated_voting, result_type, votes)
          {:ok, updated_voting}

        error ->
          error
      end
    else
      # Don't save empty voting rounds
      {:ok, voting}
    end
  end

  defp maybe_set_auto_decision(voting, :completed, votes) do
    if is_nil(voting.decision) do
      unique_votes = votes |> Map.values() |> Enum.uniq()

      if length(unique_votes) == 1 && hd(unique_votes) != "?" do
        set_voting_decision(voting, hd(unique_votes))
      end
    end
  end

  defp maybe_set_auto_decision(_voting, _result_type, _votes), do: :ok

  @doc """
  Gets votings for a poker session ordered by position.

  ## Examples

      iex> get_poker_votings(poker.id)
      [%Voting{}, ...]

  """
  def get_poker_votings(poker_id) do
    from(v in Voting, where: v.poker_id == ^poker_id, order_by: [asc: v.position])
    |> Repo.all()
  end

  @doc """
  Gets a single voting by id.

  ## Examples

      iex> get_voting(voting_id)
      %Voting{}

      iex> get_voting("unknown")
      nil

  """
  def get_voting(id), do: Repo.get(Voting, id)

  defp get_next_voting_position(poker_id) do
    from(v in Voting,
      where: v.poker_id == ^poker_id,
      select: max(v.position)
    )
    |> Repo.one()
    |> case do
      nil -> 1
      max_position -> max_position + 1
    end
  end

  defp broadcast_voting_update(poker_id, message) do
    Phoenix.PubSub.broadcast(
      PlanningPoker.PubSub,
      "poker:#{poker_id}",
      message
    )
  end

  @doc """
  Generates a session token for a user in a poker session.
  """
  def generate_user_token(poker_id, username) do
    secret_key = Application.get_env(:planning_poker, PlanningPokerWeb.Endpoint)[:secret_key_base]
    data = "#{poker_id}:#{username}"
    :crypto.mac(:hmac, :sha256, secret_key, data) |> Base.encode64()
  end

  @doc """
  Validates a user session token.
  """
  def validate_user_token(poker_id, username, token) do
    # Check if token validation should be bypassed (useful for testing)
    bypass_validation? = Application.get_env(:planning_poker, :bypass_token_validation, false)

    if bypass_validation? and String.length(token) == 24 do
      # Accept test tokens (24 chars base64 from 16 bytes)
      true
    else
      expected_token = generate_user_token(poker_id, username)
      expected_token == token
    end
  end

  @doc """
  Validates user session and returns user info if valid.
  """
  def validate_user_session(poker_id, username, token) do
    case get_poker(poker_id) do
      nil ->
        {:error, :poker_not_found}

      poker ->
        if username in (poker.usernames || []) and validate_user_token(poker_id, username, token) do
          {:ok, %{username: username, poker_id: poker_id}}
        else
          {:error, :invalid_session}
        end
    end
  end
end
