defmodule PlanningPokerWeb.ErrorHTMLTest do
  use PlanningPokerWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    # Our custom 404 template renders HTML, not just "Not Found"
    html = render_to_string(PlanningPokerWeb.ErrorHTML, "404", "html", flash: %{})
    assert html =~ "Poker Session Not Found"
    assert html =~ "404"
  end

  test "renders 500.html" do
    # Our custom 500 template renders HTML, not just "Internal Server Error"
    html = render_to_string(PlanningPokerWeb.ErrorHTML, "500", "html", flash: %{})
    assert html =~ "Internal Server Error"
    assert html =~ "500"
  end
end
