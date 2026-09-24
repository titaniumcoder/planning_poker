defmodule PlanningPokerWeb.PokerLiveTest do
  use PlanningPokerWeb.ConnCase

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  describe "voting functionality" do
    setup do
      poker = poker_fixture(%{name: "Test Poker", card_type: "fibonacci"})
      voting = voting_fixture(poker, %{title: "Test Story"})

      # Start user tracking to ensure proper state management
      @user_tracking_impl.start_user_tracking(poker.id)

      %{poker: poker, voting: voting}
    end

    defp join_and_get_live_session(conn, poker, username) do
      # Join via controller to establish session
      conn =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => username,
            "privacy_agreement" => "true"
          }
        )

      assert redirected_to(conn) == "/poker/#{poker.id}/live"

      # Access live view with session
      {:ok, view, html} = live(conn, ~p"/poker/#{poker.id}/live")
      {view, html}
    end

    test "shows start voting button for open voting", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Check that start voting button exists
      assert has_element?(view, "button", "Start Voting")
    end

    test "starts voting session when button clicked", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Click start voting
      view |> element("button", "Start Voting") |> render_click()

      # Should now show voting interface with cards
      html = render(view)
      assert html =~ "Cast Your Vote"
      # Check for fibonacci cards
      assert html =~ "1"
      assert html =~ "2"
      assert html =~ "3"
      assert html =~ "5"
      assert html =~ "8"
    end

    test "shows voting progress for participants", %{conn: conn, poker: poker} do
      # Add a second user to the poker session so voting doesn't auto-complete
      {:ok, _token} = Poker.join_poker_user(poker, "bob")

      # Connect alice first (which will mark alice as online)
      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Then mark bob as online
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())

      # Verify both users are considered unmuted and online
      unmuted_users = Poker.get_unmuted_online_users(poker.id)
      assert "alice" in unmuted_users
      assert "bob" in unmuted_users

      # Start voting
      view |> element("button", "Start Voting") |> render_click()

      # Submit a vote using more specific selector
      html = render(view)
      assert html =~ "phx-click=\"submit_vote\""

      view |> element("div[phx-click='submit_vote'][phx-value-vote='5']") |> render_click()

      # Should show voting progress (won't complete because bob hasn't voted yet)
      html = render(view)
      assert html =~ "Voting in Progress"
      assert html =~ "alice"
    end

    test "submits vote and shows confirmation", %{conn: conn, poker: poker} do
      # Add a second user to the poker session so voting doesn't auto-complete
      {:ok, _token} = Poker.join_poker_user(poker, "bob")

      # Start user tracking to properly track online/offline users
      @user_tracking_impl.start_user_tracking(poker.id)
      # Mark both users as online
      @user_tracking_impl.mark_user_online(poker.id, "alice", self())
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())

      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Start voting
      view |> element("button", "Start Voting") |> render_click()

      # Submit a vote using more specific selector
      view |> element("div[phx-click='submit_vote'][phx-value-vote='5']") |> render_click()

      # Should show the user's vote
      html = render(view)
      # User's vote should be visible
      assert html =~ "5"
    end

    test "cancels voting session", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Start voting
      view |> element("button", "Start Voting") |> render_click()

      # Cancel voting
      view |> element("button", "Cancel Voting") |> render_click()

      # Should return to normal state
      assert has_element?(view, "button", "Start Voting")
    end

    test "shows voting history after completion", %{conn: conn, poker: poker} do
      # Create voting with some history
      _voting =
        voting_fixture(poker, %{
          title: "Test Story",
          votes: [
            %{
              "result" => "completed",
              "votes" => %{"alice" => "5", "bob" => "8"},
              "participants" => ["alice", "bob"],
              "ended_at" => DateTime.utc_now()
            }
          ]
        })

      {_view, html} = join_and_get_live_session(conn, poker, "alice")

      # Should show voting history
      assert html =~ "Test Story"
      assert html =~ "alice"
      assert html =~ "5"
      assert html =~ "bob"
      assert html =~ "8"
    end

    test "disabled start voting when poker is closed", %{conn: conn, poker: poker} do
      # Close the poker session
      {:ok, closed_poker} = Poker.close_poker(poker)

      {view, _html} = join_and_get_live_session(conn, closed_poker, "alice")

      # Start voting button should be disabled
      assert has_element?(view, "button[disabled]", "Start Voting")
    end
  end

  describe "card types" do
    test "shows fibonacci cards for fibonacci poker", %{conn: conn} do
      poker = poker_fixture(%{name: "Fibonacci Poker", card_type: "fibonacci"})
      _voting = voting_fixture(poker, %{title: "Test Story"})

      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Start voting to see cards
      view |> element("button", "Start Voting") |> render_click()

      html = render(view)
      # Should show fibonacci sequence
      assert html =~ "1"
      assert html =~ "2"
      assert html =~ "3"
      assert html =~ "5"
      assert html =~ "8"
      assert html =~ "13"
      assert html =~ "20"
      assert html =~ "40"
      assert html =~ "100"
    end

    test "shows t-shirt cards for t-shirt poker", %{conn: conn} do
      poker = poker_fixture(%{name: "T-Shirt Poker", card_type: "t-shirt"})
      _voting = voting_fixture(poker, %{title: "Test Story"})

      {view, _html} = join_and_get_live_session(conn, poker, "alice")

      # Start voting to see cards
      view |> element("button", "Start Voting") |> render_click()

      html = render(view)
      # Should show t-shirt sizes
      assert html =~ "XS"
      assert html =~ "S"
      assert html =~ "M"
      assert html =~ "L"
      assert html =~ "XL"
      assert html =~ "XXL"
    end
  end
end
