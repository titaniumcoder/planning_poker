defmodule PlanningPokerWeb.PrivacyLive do
  use PlanningPokerWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Data Privacy")}
  end
end
