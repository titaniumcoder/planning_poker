defmodule PlanningPokerWeb.PokerLive do
  use PlanningPokerWeb, :live_view

  alias PlanningPoker.Poker
  alias PlanningPokerWeb.Forms.VotingForm

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  def mount(_params, session, socket) do
    # Send keep-alive every 15 seconds to ensure user stays online
    if connected?(socket) do
      Process.send_after(self(), :keep_alive, 15_000)
    end

    {:ok, assign(socket, :session, session)}
  end

  def handle_params(%{"id" => poker_id}, _url, socket) do
    username = socket.assigns.current_user
    initialize_authenticated_session(socket, poker_id, username)
  end

  def terminate(_reason, socket) do
    # Mark user as offline when LiveView terminates
    if socket.assigns[:poker_id] && socket.assigns[:user_name] do
      @user_tracking_impl.mark_user_offline(
        socket.assigns.poker_id,
        socket.assigns.user_name,
        self()
      )
    end

    :ok
  end

  # All the event handlers from the original implementation
  def handle_event("ping", _params, socket) do
    # Simple ping handler to keep connection alive - no action needed
    {:noreply, socket}
  end

  def handle_event("toggle_session_state", _params, socket) do
    %{poker: poker} = socket.assigns

    result =
      if Poker.closed?(poker) do
        Poker.reopen_poker(poker)
      else
        Poker.close_poker(poker)
      end

    case result do
      {:ok, updated_poker} ->
        if Poker.closed?(updated_poker) do
          Poker.stop_voting_server(updated_poker)
        else
          Poker.ensure_voting_server(updated_poker)
        end

        status = if Poker.closed?(updated_poker), do: "closed", else: "reopened"

        # Debug logging
        require Logger
        Logger.info("Broadcasting session_state_changed: #{status} for poker #{poker.id}")

        # Broadcast session state change to all connected users
        Phoenix.PubSub.broadcast(
          PlanningPoker.PubSub,
          "poker:#{poker.id}",
          {:session_state_changed, updated_poker}
        )

        {:noreply,
         socket
         |> assign(:poker, updated_poker)
         |> reset_voting_state()
         |> put_flash(:info, "Session #{status} successfully!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update session state")}
    end
  end

  def handle_event("delete_session", _params, socket) do
    %{poker: poker} = socket.assigns

    case Poker.delete_poker(poker) do
      {:ok, _poker} ->
        # Stop the voting server if running
        Poker.stop_voting_server(poker)

        {:noreply,
         socket
         |> put_flash(:info, "Poker session deleted successfully")
         |> push_navigate(to: ~p"/poker")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete session")}
    end
  end

  def handle_event("leave_session", _params, socket) do
    # Redirect to leave endpoint to clear session
    {:noreply, push_navigate(socket, to: ~p"/poker/#{socket.assigns.poker_id}/leave")}
  end

  def handle_event("toggle_rounds_visibility", %{"voting_id" => voting_id}, socket) do
    current_visibility = socket.assigns[:rounds_visibility] || %{}
    voting_id_int = String.to_integer(voting_id)

    new_visibility =
      Map.update(current_visibility, voting_id_int, true, fn current -> !current end)

    {:noreply, assign(socket, :rounds_visibility, new_visibility)}
  end

  def handle_event("toggle_mute", _params, socket) do
    %{poker_id: poker_id, user_name: user_name} = socket.assigns

    {:ok, _user} = @user_tracking_impl.toggle_mute_user(poker_id, user_name)
    socket = handle_user_diff(socket)
    {:noreply, socket}
  end

  def handle_event("add_voting", _params, socket) do
    voting_form = to_form(VotingForm.changeset(%VotingForm{}))

    {:noreply,
     socket
     |> assign(:show_voting_form, true)
     |> assign(:voting_form, voting_form)}
  end

  def handle_event("cancel_voting_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_voting_form, false)
     |> assign(:voting_form, nil)}
  end

  def handle_event("validate_voting", %{"voting_form" => form_params}, socket) do
    changeset =
      %VotingForm{}
      |> VotingForm.changeset(form_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :voting_form, to_form(changeset))}
  end

  def handle_event("save_voting", %{"voting_form" => form_params}, socket) do
    %{poker: poker} = socket.assigns
    changeset = VotingForm.changeset(%VotingForm{}, form_params)

    case changeset.valid? do
      true ->
        data = Ecto.Changeset.apply_changes(changeset)
        attrs = %{title: data.title, link: data.link}

        case Poker.create_voting(poker, attrs) do
          {:ok, _voting} ->
            {:noreply,
             socket
             |> assign(:show_voting_form, false)
             |> assign(:voting_form, nil)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save voting")}
        end

      false ->
        {:noreply, assign(socket, :voting_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("set_decision", %{"voting_id" => voting_id, "decision" => decision}, socket) do
    voting = Poker.get_voting(voting_id)

    case Poker.set_voting_decision(voting, String.trim(decision)) do
      {:ok, _voting} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to set decision")}
    end
  end

  def handle_event("remove_decision", %{"voting_id" => voting_id}, socket) do
    voting = Poker.get_voting(voting_id)

    case Poker.remove_voting_decision(voting) do
      {:ok, _voting} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove decision")}
    end
  end

  def handle_event("start_voting", %{"voting_id" => voting_id}, socket) do
    %{poker: poker} = socket.assigns
    voting = Poker.get_voting(voting_id)

    case Poker.start_voting_for_voting(poker, voting) do
      {:ok, participants} ->
        # Get the remaining time from the server
        remaining_time =
          case Poker.get_voting_remaining_time(poker) do
            {:ok, time} -> time
            _ -> 30
          end

        {:noreply,
         socket
         |> assign(:current_voting_id, voting_id)
         |> assign(:voting_participants, participants)
         |> assign(:voting_status, :voting)
         |> assign(:user_votes, %{})
         |> assign(:user_has_voted, false)
         |> assign(:remaining_time, remaining_time)
         |> assign(:rounds_visibility, %{})}

      {:error, :no_participants} ->
        {:noreply, put_flash(socket, :error, "No unmuted participants available for voting")}

      {:error, :voting_in_progress} ->
        {:noreply, put_flash(socket, :error, "A voting session is already in progress")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start voting")}
    end
  end

  def handle_event("submit_vote", %{"vote" => vote}, socket) do
    %{poker: poker, user_name: user_name} = socket.assigns

    case Poker.submit_vote(poker, user_name, vote) do
      :ok ->
        current_votes = socket.assigns[:user_votes] || %{}
        updated_votes = Map.put(current_votes, user_name, vote)

        # Get remaining time from server after voting
        remaining_time =
          case Poker.get_voting_remaining_time(poker) do
            {:ok, time} -> time
            _ -> socket.assigns[:remaining_time] || 30
          end

        {:noreply,
         socket
         |> assign(:user_votes, updated_votes)
         |> assign(:user_has_voted, true)
         |> assign(:remaining_time, remaining_time)}

      {:error, :not_participant} ->
        {:noreply, put_flash(socket, :error, "You are not a participant in this voting")}

      {:error, :no_voting_in_progress} ->
        {:noreply, put_flash(socket, :error, "No voting is currently in progress")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit vote")}
    end
  end

  def handle_event("cancel_voting", _params, socket) do
    %{poker: poker} = socket.assigns

    case Poker.cancel_voting_session(poker) do
      :ok ->
        {:noreply, reset_voting_state(socket)}

      {:error, :no_voting_in_progress} ->
        {:noreply, put_flash(socket, :error, "No voting is currently in progress")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel voting")}
    end
  end

  # User tracking message handlers
  def handle_info(:keep_alive, socket) do
    # Mark user as online to reset any timeout
    if socket.assigns[:poker_id] && socket.assigns[:user_name] do
      @user_tracking_impl.mark_user_online(
        socket.assigns.poker_id,
        socket.assigns.user_name,
        self()
      )
    end

    # Schedule the next keep-alive
    Process.send_after(self(), :keep_alive, 15_000)

    {:noreply, socket}
  end

  def handle_info({:user_joined, user_data}, socket) do
    socket = handle_user_diff(socket)
    {:noreply, put_flash(socket, :info, "#{user_data.username} joined")}
  end

  def handle_info({:user_came_online, user_data}, socket) do
    socket = handle_user_diff(socket)

    if user_data.username != socket.assigns.user_name do
      {:noreply, put_flash(socket, :info, "#{user_data.username} came online")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:user_went_offline, user_data}, socket) do
    socket = handle_user_diff(socket)

    if user_data.username != socket.assigns.user_name do
      {:noreply, put_flash(socket, :info, "#{user_data.username} went offline")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:user_mute_toggled, user_data}, socket) do
    socket = handle_user_diff(socket)
    status = if user_data.muted, do: "muted", else: "unmuted"
    {:noreply, put_flash(socket, :info, "#{user_data.username} #{status}")}
  end

  def handle_info({:user_left, username}, socket) do
    socket = handle_user_diff(socket)

    if username != socket.assigns.user_name do
      {:noreply, put_flash(socket, :info, "#{username} left")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:voting_created, _voting}, socket) do
    updated_poker = Poker.get_poker(socket.assigns.poker.id)
    {:noreply, assign(socket, :poker, updated_poker)}
  end

  def handle_info({:voting_updated, _voting}, socket) do
    updated_poker = Poker.get_poker(socket.assigns.poker.id)
    {:noreply, assign(socket, :poker, updated_poker)}
  end

  def handle_info({:voting_deleted, _voting}, socket) do
    updated_poker = Poker.get_poker(socket.assigns.poker.id)
    {:noreply, assign(socket, :poker, updated_poker)}
  end

  def handle_info({:voting_started}, socket) do
    {:noreply, socket}
  end

  def handle_info({:voting_session_started, voting_id}, socket) do
    case Poker.get_voting_session_state(socket.assigns.poker) do
      {:ok, state} ->
        # Get remaining time from server
        remaining_time =
          case Poker.get_voting_remaining_time(socket.assigns.poker) do
            {:ok, time} -> time
            _ -> 30
          end

        {:noreply,
         socket
         |> assign(:current_voting_id, voting_id)
         |> assign(:voting_participants, state.participants)
         |> assign(:voting_status, :voting)
         |> assign(:user_votes, %{})
         |> assign(:user_has_voted, false)
         |> assign(:remaining_time, remaining_time)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:vote_submitted, user_name, vote}, socket) do
    current_votes = socket.assigns[:user_votes] || %{}
    updated_votes = Map.put(current_votes, user_name, vote)
    {:noreply, assign(socket, :user_votes, updated_votes)}
  end

  def handle_info({:session_state_changed, updated_poker}, socket) do
    # Update poker state for all connected users
    status = if Poker.closed?(updated_poker), do: "closed", else: "reopened"

    # Debug logging
    require Logger
    Logger.info("User #{socket.assigns.user_name} received session_state_changed: #{status}")

    {:noreply,
     socket
     |> assign(:poker, updated_poker)
     |> reset_voting_state()
     |> handle_user_diff()
     |> put_flash(:info, "Session was #{status} by moderator")}
  end

  def handle_info({:voting_ended, result_type, votes}, socket) do
    if socket.assigns[:current_voting_id] do
      voting = Poker.get_voting(socket.assigns.current_voting_id)

      if voting do
        Poker.save_voting_result(voting, result_type, votes, socket.assigns.voting_participants)
      end
    end

    updated_poker = Poker.get_poker(socket.assigns.poker.id)

    {:noreply,
     socket
     |> assign(:poker, updated_poker)
     |> reset_voting_state()}
  end

  # Helper functions
  defp initialize_authenticated_session(socket, poker_id, username) do
    case Poker.get_poker(poker_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Poker session not found")
         |> push_navigate(to: ~p"/poker")}

      poker ->
        Phoenix.PubSub.subscribe(PlanningPoker.PubSub, "poker:#{poker_id}")
        Poker.ensure_voting_server(poker)

        # Mark user as online in UserTracking
        handle_user_tracking(poker_id, username)

        {:noreply,
         socket
         |> assign(:page_title, poker.name)
         |> assign(:poker_id, poker_id)
         |> assign(:poker, poker)
         |> assign(:poker_url, url(~p"/poker/#{poker_id}"))
         |> assign(:user_name, username)
         |> assign(:users, [])
         |> assign(:online_users, [])
         |> assign(:show_voting_form, false)
         |> assign(:voting_form, nil)
         |> reset_voting_state()
         |> assign(:rounds_visibility, %{})
         |> handle_user_diff()}
    end
  end

  defp handle_user_tracking(poker_id, username) do
    case @user_tracking_impl.mark_user_online(poker_id, username, self()) do
      {:ok, _user} ->
        :ok

      {:error, :user_not_found} ->
        # User doesn't exist yet, let them join first
        case @user_tracking_impl.join_user(poker_id, username) do
          {:ok, _token} ->
            @user_tracking_impl.mark_user_online(poker_id, username, self())

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp reset_voting_state(socket) do
    socket
    |> assign(:current_voting_id, nil)
    |> assign(:voting_participants, nil)
    |> assign(:voting_status, :idle)
    |> assign(:user_votes, %{})
    |> assign(:user_has_voted, false)
    |> assign(:remaining_time, nil)
    |> assign(:rounds_visibility, %{})
  end

  defp handle_user_diff(socket) do
    users = @user_tracking_impl.get_users(socket.assigns.poker_id)
    online_users = @user_tracking_impl.get_online_users(socket.assigns.poker_id)

    socket
    |> assign(:users, users)
    |> assign(:online_users, online_users)
  end
end
