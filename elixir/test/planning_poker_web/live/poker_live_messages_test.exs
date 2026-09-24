defmodule PlanningPokerWeb.PokerLiveMessagesTest do
  use PlanningPokerWeb.ConnCase

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  setup do
    poker = poker_fixture(%{name: "Messages Poker"})
    voting = voting_fixture(poker, %{title: "Message Story"})

    %{poker: poker, voting: voting}
  end

  defp join(conn, poker, username \\ "alice") do
    conn =
      post(conn, ~p"/poker/#{poker.id}",
        join_poker_form: %{"name" => username, "privacy_agreement" => "true"}
      )

    assert redirected_to(conn) == "/poker/#{poker.id}/live"

    {:ok, view, html} = live(conn, ~p"/poker/#{poker.id}/live")
    {view, html}
  end

  describe "ping" do
    test "responds to ping events", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)
      assert render_hook(view, "ping", %{}) =~ poker.name
    end
  end

  describe "start_voting error paths" do
    test "flashes an error when all participants are muted", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      # Mute the only participant
      view |> element("button[phx-click='toggle_mute']") |> render_click()

      view |> element("button", "Start Voting") |> render_click()

      assert render(view) =~ "No unmuted participants available for voting"
    end

    test "flashes an error when a voting is already in progress", %{
      conn: conn,
      poker: poker,
      voting: voting
    } do
      second_voting = voting_fixture(poker, %{title: "Second Story"})
      {view, _html} = join(conn, poker)

      view
      |> element("button[phx-click='start_voting'][phx-value-voting_id='#{voting.id}']")
      |> render_click()

      assert render(view) =~ "Cast Your Vote"

      # Trying to start another voting while one is active fails
      html = render_hook(view, "start_voting", %{"voting_id" => to_string(second_voting.id)})
      assert html =~ "A voting session is already in progress"

      # The first voting is still active
      assert Poker.get_voting_session_state(poker) |> elem(0) == :ok
      assert voting.id != second_voting.id
    end
  end

  describe "submit_vote error paths" do
    test "flashes an error when no voting is in progress", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      html = render_hook(view, "submit_vote", %{"vote" => "5"})
      assert html =~ "No voting is currently in progress"
    end

    test "flashes an error for non-participants", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      # Start a voting where "bob" is the only participant
      {:ok, _token} = Poker.join_poker_user(poker, "bob")
      @user_tracking_impl.start_user_tracking(poker.id)
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())
      @user_tracking_impl.toggle_mute_user(poker.id, "alice")

      view |> element("button", "Start Voting") |> render_click()

      html = render_hook(view, "submit_vote", %{"vote" => "5"})
      assert html =~ "You are not a participant in this voting"
    end
  end

  describe "cancel_voting error path" do
    test "flashes an error when no voting is in progress", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      html = render_hook(view, "cancel_voting", %{})
      assert html =~ "No voting is currently in progress"
    end
  end

  describe "user tracking broadcasts" do
    test "handles user_joined messages", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:user_joined, %{username: "bob"}})

      assert render(view) =~ "bob joined"
    end

    test "handles user_came_online messages for other users", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:user_came_online, %{username: "bob"}})

      assert render(view) =~ "bob came online"
    end

    test "handles user_came_online messages for the current user silently", %{
      conn: conn,
      poker: poker
    } do
      {view, _html} = join(conn, poker)

      send(view.pid, {:user_came_online, %{username: "alice"}})

      refute render(view) =~ "alice came online"
    end

    test "handles user_went_offline messages", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:user_went_offline, %{username: "bob"}})
      assert render(view) =~ "bob went offline"

      send(view.pid, {:user_went_offline, %{username: "alice"}})
      refute render(view) =~ "alice went offline"
    end

    test "handles user_mute_toggled messages", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:user_mute_toggled, %{username: "bob", muted: true}})
      assert render(view) =~ "bob muted"

      send(view.pid, {:user_mute_toggled, %{username: "bob", muted: false}})
      assert render(view) =~ "bob unmuted"
    end

    test "handles user_left messages", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:user_left, "bob"})
      assert render(view) =~ "bob left"

      send(view.pid, {:user_left, "alice"})
      refute render(view) =~ "alice left"
    end

    test "handles keep_alive messages", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, :keep_alive)

      assert render(view) =~ poker.name
    end
  end

  describe "voting broadcasts" do
    test "refreshes the poker on voting_created", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      {:ok, new_voting} = Poker.create_voting(poker, %{title: "Fresh story"})
      send(view.pid, {:voting_created, new_voting})

      assert render(view) =~ "Fresh story"
    end

    test "refreshes the poker on voting_updated", %{conn: conn, poker: poker, voting: voting} do
      {view, _html} = join(conn, poker)

      {:ok, updated} = Poker.update_voting(voting, %{title: "Renamed story"})
      send(view.pid, {:voting_updated, updated})

      assert render(view) =~ "Renamed story"
    end

    test "refreshes the poker on voting_deleted", %{conn: conn, poker: poker, voting: voting} do
      {view, _html} = join(conn, poker)
      assert render(view) =~ "Message Story"

      {:ok, deleted} = Poker.delete_voting(voting)
      send(view.pid, {:voting_deleted, deleted})

      refute render(view) =~ "Message Story"
    end

    test "ignores voting_started messages", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:voting_started})

      assert render(view) =~ poker.name
    end

    test "updates vote counts on vote_submitted", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      {:ok, _pid} = Poker.ensure_voting_server(poker)
      {:ok, _state} = Poker.start_voting_for_voting(poker, voting())

      send(view.pid, {:vote_submitted, "bob", "8"})

      assert render(view) =~ poker.name
    end

    test "handles voting_session_started with a running server", %{
      conn: conn,
      poker: poker,
      voting: voting
    } do
      {view, _html} = join(conn, poker)

      {:ok, _pid} = Poker.ensure_voting_server(poker)
      {:ok, _participants} = Poker.start_voting_for_voting(poker, voting)

      send(view.pid, {:voting_session_started, voting.id})

      assert render(view) =~ "Cast Your Vote"
    end

    test "handles voting_session_started without a running server", %{
      conn: conn,
      poker: poker,
      voting: voting
    } do
      {view, _html} = join(conn, poker)

      send(view.pid, {:voting_session_started, voting.id})

      assert render(view) =~ poker.name
    end

    test "saves results on voting_ended", %{conn: conn, poker: poker, voting: voting} do
      {view, _html} = join(conn, poker)

      {:ok, _pid} = Poker.ensure_voting_server(poker)
      {:ok, _participants} = Poker.start_voting_for_voting(poker, voting)

      send(view.pid, {:voting_ended, :completed, %{"alice" => "5"}})

      html = render(view)
      # The unanimous vote triggers an automatic decision
      assert html =~ "Decision:"

      reloaded = Poker.get_voting(voting.id)
      assert [%{"votes" => %{"alice" => "5"}}] = reloaded.votes
      assert reloaded.decision == "5"
    end

    test "handles voting_ended without an active voting", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      send(view.pid, {:voting_ended, :timeout, %{}})

      assert render(view) =~ poker.name
    end

    test "handles session_state_changed", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      {:ok, _closed} = Poker.close_poker(poker)
      send(view.pid, {:session_state_changed, Poker.get_poker(poker.id)})

      assert render(view) =~ "Session was closed by moderator"
    end
  end

  # Helper to build a throwaway voting struct for broadcast tests
  defp voting do
    %PlanningPoker.Poker.Voting{id: Ecto.UUID.generate()}
  end
end
