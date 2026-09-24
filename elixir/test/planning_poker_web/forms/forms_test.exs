defmodule PlanningPokerWeb.FormsTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias PlanningPokerWeb.Forms.CreatePokerForm
  alias PlanningPokerWeb.Forms.JoinPokerForm
  alias PlanningPokerWeb.Forms.VotingForm

  describe "CreatePokerForm" do
    test "is valid with all required fields" do
      changeset =
        CreatePokerForm.changeset(%CreatePokerForm{}, %{
          "name" => "Sprint 10",
          "username" => "moderator",
          "card_type" => "fibonacci",
          "privacy_agreement" => "true"
        })

      assert changeset.valid?
      data = Changeset.apply_changes(changeset)
      assert data.name == "Sprint 10"
      assert data.username == "moderator"
      assert data.card_type == "fibonacci"
    end

    test "defaults the card type to fibonacci" do
      changeset = CreatePokerForm.changeset(%CreatePokerForm{}, %{})
      assert Changeset.get_field(changeset, :card_type) == "fibonacci"
    end

    test "requires name and username" do
      changeset = CreatePokerForm.changeset(%CreatePokerForm{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
      assert {"can't be blank", _} = changeset.errors[:username]
    end

    test "rejects names and usernames longer than 100 characters" do
      long = String.duplicate("a", 101)

      changeset =
        CreatePokerForm.changeset(%CreatePokerForm{}, %{"name" => long, "username" => long})

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:name]
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:username]
    end

    test "rejects unknown card types" do
      changeset =
        CreatePokerForm.changeset(%CreatePokerForm{}, %{
          "name" => "Sprint",
          "username" => "moderator",
          "card_type" => "roman-numerals"
        })

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:card_type]
    end

    test "requires the privacy agreement to be accepted" do
      changeset =
        CreatePokerForm.changeset(%CreatePokerForm{}, %{
          "name" => "Sprint",
          "username" => "moderator",
          "privacy_agreement" => "false"
        })

      refute changeset.valid?
      assert {"must be accepted", _} = changeset.errors[:privacy_agreement]
    end
  end

  describe "JoinPokerForm" do
    test "is valid with name and accepted privacy agreement" do
      changeset =
        JoinPokerForm.changeset(%JoinPokerForm{}, %{
          "name" => "alice",
          "privacy_agreement" => "true"
        })

      assert changeset.valid?
    end

    test "requires the name" do
      changeset = JoinPokerForm.changeset(%JoinPokerForm{}, %{"privacy_agreement" => "true"})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end

    test "rejects names longer than 100 characters" do
      changeset =
        JoinPokerForm.changeset(%JoinPokerForm{}, %{
          "name" => String.duplicate("a", 101),
          "privacy_agreement" => "true"
        })

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:name]
    end

    test "requires the privacy agreement with a custom message" do
      changeset =
        JoinPokerForm.changeset(%JoinPokerForm{}, %{
          "name" => "alice",
          "privacy_agreement" => "false"
        })

      refute changeset.valid?

      assert {"You must agree to the data privacy policy", _} =
               changeset.errors[:privacy_agreement]
    end
  end

  describe "VotingForm" do
    test "is valid with a title" do
      changeset = VotingForm.changeset(%VotingForm{}, %{"title" => "Story estimation"})
      assert changeset.valid?
    end

    test "is valid with a proper link" do
      changeset =
        VotingForm.changeset(%VotingForm{}, %{
          "title" => "Story estimation",
          "link" => "https://example.com/story/1"
        })

      assert changeset.valid?
    end

    test "requires the title" do
      changeset = VotingForm.changeset(%VotingForm{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:title]
    end

    test "rejects titles longer than 200 characters" do
      changeset =
        VotingForm.changeset(%VotingForm{}, %{"title" => String.duplicate("a", 201)})

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:title]
    end

    test "rejects links longer than 500 characters" do
      changeset =
        VotingForm.changeset(%VotingForm{}, %{
          "title" => "Story",
          "link" => "https://example.com/" <> String.duplicate("a", 500)
        })

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:link]
    end

    test "rejects decisions longer than 100 characters" do
      changeset =
        VotingForm.changeset(%VotingForm{}, %{
          "title" => "Story",
          "decision" => String.duplicate("a", 101)
        })

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:decision]
    end

    test "rejects invalid links" do
      for link <- ["not a url", "ftp://example.com", "https://", "example.com"] do
        changeset =
          VotingForm.changeset(%VotingForm{}, %{"title" => "Story", "link" => link})

        refute changeset.valid?, "expected #{inspect(link)} to be invalid"
        assert {"must be a valid URL", _} = changeset.errors[:link]
      end
    end

    test "allows an empty link" do
      changeset = VotingForm.changeset(%VotingForm{}, %{"title" => "Story", "link" => ""})
      assert changeset.valid?
    end
  end
end
