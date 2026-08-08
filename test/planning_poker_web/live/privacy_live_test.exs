defmodule PlanningPokerWeb.PrivacyLiveTest do
  use PlanningPokerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the data privacy policy", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/privacy")

    assert html =~ "Data Privacy Policy"
    assert html =~ "What Data We Collect"
  end
end
