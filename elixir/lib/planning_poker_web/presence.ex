defmodule PlanningPokerWeb.Presence do
  @moduledoc """
  Provides presence tracking functionality for poker sessions.
  """

  use Phoenix.Presence,
    otp_app: :planning_poker,
    pubsub_server: PlanningPoker.PubSub
end
