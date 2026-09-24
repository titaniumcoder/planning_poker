defmodule PlanningPoker.PokerTest do
  use PlanningPoker.DataCase, async: true

  alias PlanningPoker.Poker

  describe "poker" do
    alias PlanningPoker.Poker.Poker, as: SinglePoker

    import PlanningPoker.PokerFixtures

    @invalid_attrs %{name: nil}

    test "get_poker/1 returns the poker with given id" do
      poker = poker_fixture()
      retrieved_poker = Poker.get_poker(poker.id)

      # Compare without associations for test consistency
      assert retrieved_poker.id == poker.id
      assert retrieved_poker.name == poker.name
      assert retrieved_poker.card_type == poker.card_type
      # Votings should be loaded as an empty list
      assert retrieved_poker.votings == []
    end

    test "create_poker/1 with valid data creates a poker" do
      valid_attrs = %{
        name: "some name",
        card_type: "fibonacci"
      }

      assert {:ok, %SinglePoker{} = poker} = Poker.create_poker(valid_attrs)
      assert poker.name == "some name"
      assert poker.card_type == "fibonacci"
    end

    test "create_poker/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Poker.create_poker(@invalid_attrs)
    end

    test "update_poker/2 with valid data updates the poker" do
      poker = poker_fixture()

      update_attrs = %{
        name: "some updated name",
        card_type: "t-shirt"
      }

      assert {:ok, %SinglePoker{} = poker} = Poker.update_poker(poker, update_attrs)
      assert poker.name == "some updated name"
      assert poker.card_type == "t-shirt"
    end

    test "update_poker/2 with invalid data returns error changeset" do
      poker = poker_fixture()
      assert {:error, %Ecto.Changeset{}} = Poker.update_poker(poker, @invalid_attrs)

      # Compare the reloaded poker with the original (both now have votings loaded)
      retrieved_poker = Poker.get_poker(poker.id)
      assert retrieved_poker.id == poker.id
      assert retrieved_poker.name == poker.name
    end

    test "end_poker/1 deletes the poker" do
      poker = poker_fixture()
      assert {:ok, %SinglePoker{}} = Poker.end_poker(poker)
      assert nil == Poker.get_poker(poker.id)
    end

    test "change_poker/1 returns a poker changeset" do
      poker = poker_fixture()
      assert %Ecto.Changeset{} = Poker.change_poker(poker)
    end

    test "close_poker/1 sets the closed_at timestamp" do
      poker = poker_fixture()
      assert poker.closed_at == nil

      assert {:ok, %SinglePoker{} = closed_poker} = Poker.close_poker(poker)
      assert closed_poker.closed_at != nil
      assert Poker.closed?(closed_poker) == true
    end

    test "reopen_poker/1 clears the closed_at timestamp" do
      poker = poker_fixture()

      # First close the poker
      {:ok, closed_poker} = Poker.close_poker(poker)
      assert Poker.closed?(closed_poker) == true

      # Then reopen it
      assert {:ok, %SinglePoker{} = reopened_poker} = Poker.reopen_poker(closed_poker)
      assert reopened_poker.closed_at == nil
      assert Poker.closed?(reopened_poker) == false
    end

    test "closed?/1 returns correct status" do
      poker = poker_fixture()
      assert Poker.closed?(poker) == false

      {:ok, closed_poker} = Poker.close_poker(poker)
      assert Poker.closed?(closed_poker) == true

      {:ok, reopened_poker} = Poker.reopen_poker(closed_poker)
      assert Poker.closed?(reopened_poker) == false
    end
  end
end
