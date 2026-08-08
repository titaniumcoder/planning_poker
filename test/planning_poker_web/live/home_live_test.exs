defmodule PlanningPokerWeb.HomeLiveTest do
  use PlanningPokerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the landing page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Planning Poker"
    assert html =~ "Start a New Session"
    assert html =~ "Join Existing Session"
    assert html =~ "Create Planning Poker"
    assert html =~ "View Source Code"
  end

  test "links to the create page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert view
           |> element("a[href='/poker']", "Create Planning Poker")
           |> has_element?()
  end
end
