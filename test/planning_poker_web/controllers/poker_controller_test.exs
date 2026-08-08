defmodule PlanningPokerWeb.PokerControllerTest do
  use PlanningPokerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures

  alias PlanningPoker.Poker

  defp join_via_form(conn, poker, username \\ "Test User") do
    post(conn, ~p"/poker/#{poker.id}",
      join_poker_form: %{"name" => username, "privacy_agreement" => "true"}
    )
  end

  defp conn_with_session(conn, poker, username, token) do
    Plug.Test.init_test_session(conn, %{
      "poker_#{poker.id}" => %{
        "username" => username,
        "token" => token,
        "poker_id" => poker.id
      }
    })
  end

  describe "join/2" do
    test "returns 404 for an invalid uuid", %{conn: conn} do
      conn = get(conn, "/poker/not-a-uuid")
      assert html_response(conn, 404) =~ "Poker Session Not Found"
    end

    test "redirects straight to the live view with a valid session", %{conn: conn} do
      poker = poker_fixture()
      conn = join_via_form(conn, poker)
      assert redirected_to(conn) == "/poker/#{poker.id}/live"

      # Visiting the join page again reuses the stored session
      conn = get(conn, ~p"/poker/#{poker.id}")
      assert redirected_to(conn) == "/poker/#{poker.id}/live"
    end

    test "renders the join form when the stored token is invalid", %{conn: conn} do
      poker = poker_fixture()
      {:ok, _token} = Poker.join_poker_user(poker, "Test User")

      conn =
        conn
        |> conn_with_session(poker, "Test User", "invalid-token")
        |> get(~p"/poker/#{poker.id}")

      html = html_response(conn, 200)
      assert html =~ poker.name
      assert html =~ "Join Session"
    end
  end

  describe "identify_user/2" do
    test "returns 404 for an invalid uuid", %{conn: conn} do
      conn =
        post(conn, "/poker/not-a-uuid",
          join_poker_form: %{"name" => "alice", "privacy_agreement" => "true"}
        )

      assert html_response(conn, 404)
    end

    test "returns 404 when the poker does not exist", %{conn: conn} do
      missing_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/poker/#{missing_id}",
          join_poker_form: %{"name" => "alice", "privacy_agreement" => "true"}
        )

      assert html_response(conn, 404)
    end

    test "welcomes back a user with an existing valid session", %{conn: conn} do
      poker = poker_fixture()
      conn = join_via_form(conn, poker, "alice")
      assert redirected_to(conn) == "/poker/#{poker.id}/live"

      conn = join_via_form(conn, poker, "alice")
      assert redirected_to(conn) == "/poker/#{poker.id}/live"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome back, alice!"
    end

    test "rejoins when the stored session token is invalid", %{conn: conn} do
      poker = poker_fixture()
      {:ok, _token} = Poker.join_poker_user(poker, "alice")

      conn =
        conn
        |> conn_with_session(poker, "alice", "invalid-token")
        |> join_via_form(poker, "alice")

      # The username is already taken, so the rejoin attempt fails
      assert html_response(conn, 200) =~ "Username is already taken"
    end
  end

  describe "leave/2" do
    test "clears the session and redirects home", %{conn: conn} do
      poker = poker_fixture()
      conn = join_via_form(conn, poker)
      assert redirected_to(conn) == "/poker/#{poker.id}/live"

      conn = get(conn, ~p"/poker/#{poker.id}/leave")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You have left the poker session"

      # The live view is no longer accessible with the cleared session
      expected_path = "/poker/#{poker.id}"

      assert {:error, {:live_redirect, %{to: ^expected_path}}} =
               live(conn, ~p"/poker/#{poker.id}/live")
    end
  end

  describe "join_creator/2" do
    test "sets up the creator session and redirects to the live view", %{conn: conn} do
      poker = poker_fixture()
      {:ok, token} = Poker.join_poker_user(poker, "creator")

      conn = get(conn, ~p"/poker/#{poker.id}/creator/creator/#{token}")
      assert redirected_to(conn) == "/poker/#{poker.id}/live"

      # The session allows accessing the live view
      {:ok, _view, html} = live(conn, ~p"/poker/#{poker.id}/live")
      assert html =~ poker.name
      assert html =~ "creator (You)"
    end
  end
end
