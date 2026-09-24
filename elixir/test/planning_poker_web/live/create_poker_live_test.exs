defmodule PlanningPokerWeb.CreatePokerLiveTest do
  use PlanningPokerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  @user_tracking_impl Application.compile_env(
                        :planning_poker,
                        :user_tracking_impl,
                        PlanningPoker.UserTrackingContext
                      )

  describe "Join Page (Controller)" do
    setup do
      poker = poker_fixture()
      %{poker: poker}
    end

    test "renders poker join page with form", %{conn: conn, poker: poker} do
      conn = get(conn, ~p"/poker/#{poker.id}")

      assert html_response(conn, 200)
      html = html_response(conn, 200)
      assert html =~ poker.name
      assert html =~ "name=\"join_poker_form[name]\""
      assert html =~ "name=\"join_poker_form[privacy_agreement]\""
      assert html =~ "data privacy policy"
      assert html =~ "Your Name"
      assert html =~ "Join Session"
    end

    test "requires privacy agreement to join", %{conn: conn, poker: poker} do
      # Try to join without privacy agreement
      conn =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => "Test User",
            "privacy_agreement" => "false"
          }
        )

      # Should stay on join form with error
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      assert html =~ poker.name
      assert html =~ "Your Name"
    end

    test "allows joining with name and privacy agreement", %{conn: conn, poker: poker} do
      # Join with valid data
      conn =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => "Test User",
            "privacy_agreement" => "true"
          }
        )

      # Should redirect to live view
      assert redirected_to(conn) == "/poker/#{poker.id}/live"
    end

    test "validates required name field", %{conn: conn, poker: poker} do
      # Try to join without name
      conn =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => "",
            "privacy_agreement" => "true"
          }
        )

      # Should stay on join form
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      assert html =~ poker.name
      assert html =~ "Your Name"
    end

    test "validates both name and privacy agreement are required", %{conn: conn, poker: poker} do
      # Try to join with empty form
      conn =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => "",
            "privacy_agreement" => "false"
          }
        )

      # Should stay on join form
      assert html_response(conn, 200)
      html = html_response(conn, 200)
      assert html =~ poker.name
      assert html =~ "Your Name"
    end

    test "blocks already taken username", %{conn: conn, poker: poker} do
      # First user joins successfully
      conn1 =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => "Test User",
            "privacy_agreement" => "true"
          }
        )

      assert redirected_to(conn1) == "/poker/#{poker.id}/live"

      # Second user tries same username
      conn2 =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => "Test User",
            "privacy_agreement" => "true"
          }
        )

      # Should stay on join form with error
      assert html_response(conn2, 200)
      html = html_response(conn2, 200)
      assert html =~ "Username is already taken"
    end

    test "shows 404 when poker does not exist", %{conn: conn} do
      nonexistent_uuid = "00000000-0000-0000-0000-000000000000"

      conn = get(conn, ~p"/poker/#{nonexistent_uuid}")
      assert response(conn, 404)
      assert html_response(conn, 404) =~ "Poker Session Not Found"
    end
  end

  describe "Authenticated Live Session" do
    setup do
      poker = poker_fixture()
      %{poker: poker}
    end

    defp join_and_get_live_session(conn, poker, username \\ "Test User") do
      # First join via controller to get session
      conn =
        post(conn, ~p"/poker/#{poker.id}",
          join_poker_form: %{
            "name" => username,
            "privacy_agreement" => "true"
          }
        )

      assert redirected_to(conn) == "/poker/#{poker.id}/live"

      # Now access the live view with the session
      {:ok, view, html} = live(conn, ~p"/poker/#{poker.id}/live")
      {view, html}
    end

    test "shows authenticated session after joining", %{conn: conn, poker: poker} do
      {_view, html} = join_and_get_live_session(conn, poker)

      assert html =~ poker.name
      assert html =~ "FIBONACCI"
      assert html =~ "Terminate"
      assert html =~ "Leave"
      assert html =~ "Active Users (1)"
      assert html =~ "Test User (You)"
      assert html =~ "Share:"
    end

    test "redirects to join page when accessing live view without session", %{
      conn: conn,
      poker: poker
    } do
      # Try to access live view directly without session
      result = live(conn, ~p"/poker/#{poker.id}/live")

      # Should redirect to join page
      expected_path = "/poker/#{poker.id}"
      assert {:error, {:live_redirect, %{to: ^expected_path, flash: _}}} = result
    end

    test "toggle_mute changes mute status and updates UI", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker)

      # Initially not muted - check for the mute button by its tooltip
      assert has_element?(view, "button[data-tip*='Mute yourself']")

      view |> element("button[phx-click='toggle_mute']") |> render_click()

      # Should be muted now - check for unmute tooltip
      assert has_element?(view, "button[data-tip*='Unmute yourself']")

      view |> element("button[phx-click='toggle_mute']") |> render_click()

      # Should be unmuted again
      assert has_element?(view, "button[data-tip*='Mute yourself']")
    end

    test "toggle_session_state changes session status", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker)

      assert has_element?(view, "button", "Terminate")

      view |> element("button[phx-click='toggle_session_state']") |> render_click()

      assert has_element?(view, "button", "Reopen")
      # The flash message will be "Session was closed by moderator" since
      # the broadcast message overwrites the success message in tests
      assert render(view) =~ "Session was closed by moderator"

      view |> element("button[phx-click='toggle_session_state']") |> render_click()

      assert has_element?(view, "button", "Terminate")
      assert render(view) =~ "Session was reopened by moderator"
    end

    test "leave_session navigates back to home", %{conn: conn, poker: poker} do
      {view, html} = join_and_get_live_session(conn, poker)

      assert html =~ "Test User (You)"

      view |> element("button[phx-click='leave_session']") |> render_click()

      # Should redirect to home via leave controller action
      assert_redirect(view, "/poker/#{poker.id}/leave")
    end

    test "user list shows correct mute status styling", %{conn: conn, poker: poker} do
      {view, html} = join_and_get_live_session(conn, poker)

      # Check initial state - not muted
      refute html =~ "bg-error"

      view |> element("button[phx-click='toggle_mute']") |> render_click()

      # Should show muted styling
      html = render(view)
      assert html =~ "bg-error"
    end

    test "shows card type badge", %{conn: conn, poker: poker} do
      {_view, html} = join_and_get_live_session(conn, poker)

      assert html =~ "FIBONACCI"
    end

    test "current user appears first with highlighted background", %{conn: conn, poker: poker} do
      {_view, html} = join_and_get_live_session(conn, poker)

      assert html =~ "bg-primary text-primary-content"
      assert html =~ "Test User (You)"
    end

    test "copy URL functionality is present", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker)

      assert has_element?(view, "#copy-poker-url")
      assert has_element?(view, "input[type='hidden']#poker-url-input")
      assert has_element?(view, "button[title='Copy URL']")
    end

    test "active users section shows only when poker is open and has online users", %{
      conn: conn,
      poker: poker
    } do
      # Add a second user to the poker session
      {:ok, _token} = Poker.join_poker_user(poker, "bob")

      @user_tracking_impl.start_user_tracking(poker.id)
      @user_tracking_impl.mark_user_online(poker.id, "Test User", self())
      @user_tracking_impl.mark_user_online(poker.id, "bob", self())

      {view, html} = join_and_get_live_session(conn, poker)

      # Should show active users section when poker is open and has online users
      assert html =~ "Active Users (2)"
      assert has_element?(view, "h3", "Active Users (2)")

      # Close the poker session
      view |> element("button[phx-click='toggle_session_state']") |> render_click()

      # After closing, active users section should be hidden
      html = render(view)
      refute html =~ "Active Users"
      refute has_element?(view, "h3", "Active Users")
    end

    test "active users count shows only online users, not all users", %{conn: conn, poker: poker} do
      # Add multiple users to the poker session
      {:ok, _token1} = Poker.join_poker_user(poker, "alice")
      {:ok, _token2} = Poker.join_poker_user(poker, "bob")
      {:ok, _token3} = Poker.join_poker_user(poker, "charlie")

      @user_tracking_impl.start_user_tracking(poker.id)

      # Mark Test User (current user) and alice as online
      @user_tracking_impl.mark_user_online(poker.id, "Test User", self())
      @user_tracking_impl.mark_user_online(poker.id, "alice", self())
      # bob and charlie are joined but not marked as online (offline)

      {_view, html} = join_and_get_live_session(conn, poker)

      # Should show only 2 online users in the count, not all 4 users
      assert html =~ "Active Users (2)"
      refute html =~ "Active Users (4)"

      # Verify the online users are displayed
      assert html =~ "Test User (You)"
      assert html =~ "alice"

      # Verify offline users are shown with strikethrough
      assert html =~ "line-through"
    end

    test "active users section is hidden when poker is closed", %{conn: conn, poker: poker} do
      @user_tracking_impl.start_user_tracking(poker.id)

      {view, html} = join_and_get_live_session(conn, poker)

      # Initially should show active users section
      assert html =~ "Active Users (1)"

      # Close the poker session
      view |> element("button[phx-click='toggle_session_state']") |> render_click()

      # After closing, active users section should be hidden
      html = render(view)
      refute html =~ "Active Users"
    end
  end
end
