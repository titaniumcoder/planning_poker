defmodule PlanningPoker.PokerFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PlanningPoker.Poker` context.
  """

  @doc """
  Generate a poker.
  """
  def poker_fixture(attrs \\ %{}) do
    {:ok, poker} =
      attrs
      |> Enum.into(%{
        name: "some name",
        card_type: "fibonacci"
      })
      |> PlanningPoker.Poker.create_poker()

    poker
  end

  @doc """
  Generate a voting for a poker.
  """
  def voting_fixture(poker, attrs \\ %{}) do
    {:ok, voting} =
      attrs
      |> Enum.into(%{
        title: "some title",
        link: "https://example.com"
      })
      |> (&PlanningPoker.Poker.create_voting(poker, &1)).()

    voting
  end

  @doc """
  Generate a poker user for a poker.
  """
  def join_poker_user_fixture(poker, username) do
    {:ok, token} = PlanningPoker.Poker.join_poker_user(poker, username)
    %{username: username, token: token}
  end
end
