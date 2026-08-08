defmodule PlanningPokerWeb.PokerLiveVotingFormTest do
  use PlanningPokerWeb.ConnCase

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  setup do
    poker = poker_fixture(%{name: "Form Poker"})
    %{poker: poker}
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

  describe "voting form" do
    test "add_voting opens the voting form", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)

      refute has_element?(view, "#voting-form")

      view |> element("button", "Add a Voting") |> render_click()

      assert has_element?(view, "#voting-form")
      assert render(view) =~ "Create New Voting"
    end

    test "validate_voting shows validation errors", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)
      view |> element("button", "Add a Voting") |> render_click()

      html =
        view
        |> form("#voting-form", voting_form: %{"title" => ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "save_voting rejects invalid data", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)
      view |> element("button", "Add a Voting") |> render_click()

      html =
        view
        |> form("#voting-form", voting_form: %{"title" => "", "link" => "not-a-url"})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert has_element?(view, "#voting-form")
    end

    test "save_voting creates a voting and hides the form", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)
      view |> element("button", "Add a Voting") |> render_click()

      view
      |> form("#voting-form",
        voting_form: %{"title" => "New story", "link" => "https://example.com/story"}
      )
      |> render_submit()

      refute has_element?(view, "#voting-form")
      assert render(view) =~ "New story"
      assert Poker.get_poker(poker.id).votings |> length() == 1
    end

    test "cancel_voting_form hides the form", %{conn: conn, poker: poker} do
      {view, _html} = join(conn, poker)
      view |> element("button", "Add a Voting") |> render_click()
      assert has_element?(view, "#voting-form")

      view |> element("button", "Cancel") |> render_click()

      refute has_element?(view, "#voting-form")
    end
  end

  describe "decisions" do
    test "set_decision stores the decision", %{conn: conn, poker: poker} do
      _voting = voting_fixture(poker, %{title: "Story with decision"})
      {view, _html} = join(conn, poker)

      view
      |> form("form[phx-submit='set_decision']", %{"decision" => "5 points"})
      |> render_submit()

      html = render(view)
      assert html =~ "Decision:"
      assert html =~ "5 points"
    end

    test "remove_decision clears the decision", %{conn: conn, poker: poker} do
      _voting = voting_fixture(poker, %{title: "Decided story", decision: "5"})
      {view, html} = join(conn, poker)

      assert html =~ "Decision:"
      assert html =~ "5"

      view |> element("button", "Remove Decision") |> render_click()

      html = render(view)
      refute html =~ "Decision:"
    end
  end

  describe "voting rounds visibility" do
    test "toggles visibility of previous rounds", %{conn: conn, poker: poker} do
      _voting =
        voting_fixture(poker, %{
          title: "Multi round story",
          votes: [
            %{
              "result" => "completed",
              "votes" => %{"alice" => "3"},
              "participants" => ["alice"],
              "ended_at" => DateTime.utc_now()
            },
            %{
              "result" => "completed",
              "votes" => %{"alice" => "5"},
              "participants" => ["alice"],
              "ended_at" => DateTime.utc_now()
            }
          ]
        })

      {view, html} = join(conn, poker)

      # By default only the latest round is shown
      assert html =~ "ROUND #2"
      refute html =~ "ROUND #1"
      assert html =~ "Show #1 previous round"

      view |> element("button", "Show #1 previous round") |> render_click()

      html = render(view)
      assert html =~ "ROUND #1"
      assert html =~ "ROUND #2"
      assert html =~ "Show only latest round"

      view |> element("button", "Show only latest round") |> render_click()

      html = render(view)
      refute html =~ "ROUND #1"
      assert html =~ "ROUND #2"
    end
  end
end
