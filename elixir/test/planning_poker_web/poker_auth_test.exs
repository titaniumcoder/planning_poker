defmodule PlanningPokerWeb.PokerAuthTest do
  use PlanningPokerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PlanningPoker.PokerFixtures

  test "redirects for an invalid poker id", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/poker/not-a-uuid"}}} =
             live(conn, "/poker/not-a-uuid/live")
  end

  test "redirects for a nonexistent poker", %{conn: conn} do
    missing_id = Ecto.UUID.generate()
    expected_path = "/poker/#{missing_id}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             live(conn, "/poker/#{missing_id}/live")
  end

  test "redirects when the session poker id does not match", %{conn: conn} do
    poker = poker_fixture()
    other_poker = poker_fixture()

    conn =
      Plug.Test.init_test_session(conn, %{
        "poker_#{poker.id}" => %{
          "username" => "alice",
          "token" => "some-token",
          "poker_id" => other_poker.id
        }
      })

    expected_path = "/poker/#{poker.id}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             live(conn, "/poker/#{poker.id}/live")
  end

  test "redirects when the user is no longer part of the session", %{conn: conn} do
    poker = poker_fixture()

    conn =
      Plug.Test.init_test_session(conn, %{
        "poker_#{poker.id}" => %{
          "username" => "ghost",
          "token" => "some-token",
          "poker_id" => poker.id
        }
      })

    expected_path = "/poker/#{poker.id}"

    assert {:error, {:live_redirect, %{to: ^expected_path}}} =
             live(conn, "/poker/#{poker.id}/live")
  end

  test "allows access for a valid session", %{conn: conn} do
    poker = poker_fixture()
    {:ok, token} = PlanningPoker.Poker.join_poker_user(poker, "alice")

    conn =
      Plug.Test.init_test_session(conn, %{
        "poker_#{poker.id}" => %{
          "username" => "alice",
          "token" => token,
          "poker_id" => poker.id
        }
      })

    assert {:ok, _view, html} = live(conn, "/poker/#{poker.id}/live")
    assert html =~ poker.name
  end
end
