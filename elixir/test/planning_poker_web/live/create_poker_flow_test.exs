defmodule PlanningPokerWeb.CreatePokerFlowTest do
  use PlanningPokerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PlanningPoker.Poker

  describe "create poker page" do
    test "renders the create form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/poker")

      assert html =~ "Create Planning Poker"
      assert html =~ "Session Name"
      assert html =~ "Your Name"
      assert html =~ "Card Type"
      assert html =~ "data privacy policy"
      assert html =~ "Create &amp; Join Session"
    end

    test "shows validation errors when submitting invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/poker")

      html =
        view
        |> form("#create-poker-form",
          create_poker_form: %{
            "name" => "",
            "username" => "",
            "card_type" => "fibonacci",
            "privacy_agreement" => "false"
          }
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert html =~ "must be accepted"
    end

    test "validates changes on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/poker")

      html =
        view
        |> form("#create-poker-form",
          create_poker_form: %{"name" => "", "username" => "alice"}
        )
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "creates a poker session and redirects to the creator join url", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/poker")

      view
      |> form("#create-poker-form",
        create_poker_form: %{
          "name" => "Sprint 10 Planning",
          "username" => "moderator",
          "card_type" => "t-shirt",
          "privacy_agreement" => "true"
        }
      )
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert flash["info"] == "Poker session created successfully!"

      assert [_, "poker", poker_id, "creator", "moderator", _token] =
               String.split(path, "/")

      poker = Poker.get_poker(poker_id)
      assert poker.name == "Sprint 10 Planning"
      assert poker.card_type == "t-shirt"
      assert "moderator" in poker.usernames
    end

    test "rejects an invalid card type at the changeset level" do
      changeset =
        PlanningPokerWeb.Forms.CreatePokerForm.changeset(
          %PlanningPokerWeb.Forms.CreatePokerForm{},
          %{
            "name" => "Sprint 10 Planning",
            "username" => "moderator",
            "card_type" => "invalid-type",
            "privacy_agreement" => "true"
          }
        )

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:card_type]
    end
  end
end
