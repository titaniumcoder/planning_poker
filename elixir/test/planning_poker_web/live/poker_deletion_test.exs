defmodule PlanningPokerWeb.PokerDeletionTest do
  use PlanningPokerWeb.ConnCase

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures
  alias PlanningPoker.Poker

  setup do
    poker = poker_fixture()
    %{poker: poker}
  end

  describe "Manual Poker Deletion" do
    test "shows Delete button when session is terminated", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker)

      # First, terminate the session
      view |> element("button", "Terminate") |> render_click()

      html = render(view)

      # Should show Reopen and Delete buttons
      assert html =~ "Reopen"
      assert html =~ "Delete"
      assert html =~ "Permanently delete this poker session"
    end

    test "delete_session event deletes poker and redirects", %{conn: conn, poker: poker} do
      {view, _html} = join_and_get_live_session(conn, poker)

      # Terminate the session first
      view |> element("button", "Terminate") |> render_click()

      # Verify poker exists before deletion
      assert Poker.get_poker(poker.id) != nil

      # Click Delete button - this should redirect
      view |> element("button", "Delete") |> render_click()

      # Check that we were redirected
      assert_redirect(view, "/poker")

      # Verify poker is deleted
      assert Poker.get_poker(poker.id) == nil
    end

    test "delete button only shows for terminated sessions", %{conn: conn, poker: poker} do
      {_view, html} = join_and_get_live_session(conn, poker)

      # Active session should not show Delete button
      refute html =~ "Delete"
      assert html =~ "Terminate"
      assert html =~ "Leave"
    end
  end

  defp join_and_get_live_session(conn, poker) do
    # Join the poker session using the correct route
    conn =
      post(conn, ~p"/poker/#{poker.id}", %{
        "join_poker_form" => %{"name" => "Test User", "privacy_agreement" => "true"}
      })

    # Follow the redirect
    conn = get(conn, redirected_to(conn))

    # Get the live session
    {:ok, view, html} = live(conn, ~p"/poker/#{poker.id}/live")
    {view, html}
  end
end
