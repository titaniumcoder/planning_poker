defmodule PlanningPokerWeb.HomeLive do
  use PlanningPokerWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Planning Poker")}
  end
end
