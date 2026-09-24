defmodule PlanningPokerWeb.PokerController do
  use PlanningPokerWeb, :controller
  import Phoenix.Component

  alias PlanningPoker.Poker
  alias PlanningPokerWeb.Forms.JoinPokerForm

  def join(conn, %{"id" => poker_id}) do
    if valid_uuid?(poker_id) do
      case Poker.get_poker(poker_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> put_view(html: PlanningPokerWeb.ErrorHTML)
          |> render(:"404")

        poker ->
          handle_poker_session(conn, poker, poker_id)
      end
    else
      conn
      |> put_status(:not_found)
      |> put_view(html: PlanningPokerWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  defp handle_poker_session(conn, poker, poker_id) do
    case get_session(conn, "poker_#{poker_id}") do
      %{"username" => username, "token" => token}
      when is_binary(username) and is_binary(token) ->
        validate_and_redirect(conn, poker, poker_id, username, token)

      _ ->
        render_join_form(conn, poker)
    end
  end

  defp validate_and_redirect(conn, poker, poker_id, username, token) do
    if Poker.validate_user_token(poker_id, username, token) do
      redirect(conn, to: ~p"/poker/#{poker_id}/live")
    else
      conn
      |> delete_session("poker_#{poker_id}")
      |> render_join_form(poker)
    end
  end

  def identify_user(conn, %{"id" => poker_id, "join_poker_form" => form_params}) do
    if valid_uuid?(poker_id) do
      case Poker.get_poker(poker_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> put_view(html: PlanningPokerWeb.ErrorHTML)
          |> render(:"404")

        poker ->
          process_join_form(conn, poker, poker_id, form_params)
      end
    else
      conn
      |> put_status(:not_found)
      |> put_view(html: PlanningPokerWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  defp process_join_form(conn, poker, poker_id, form_params) do
    changeset = JoinPokerForm.changeset(%JoinPokerForm{}, form_params)

    if changeset.valid? do
      data = Ecto.Changeset.apply_changes(changeset)
      username = String.trim(data.name)
      handle_user_session(conn, poker, poker_id, username, changeset)
    else
      render_join_form(conn, poker, to_form(changeset))
    end
  end

  defp handle_user_session(conn, poker, poker_id, username, changeset) do
    existing_session = get_session(conn, "poker_#{poker_id}")

    case existing_session do
      %{"username" => ^username, "token" => token} when is_binary(token) ->
        handle_existing_session(conn, poker_id, username, token, poker, changeset)

      _ ->
        attempt_user_join(conn, poker, username, changeset, poker_id)
    end
  end

  defp handle_existing_session(conn, poker_id, username, token, poker, changeset) do
    if Poker.validate_user_token(poker_id, username, token) do
      conn
      |> put_flash(:info, "Welcome back, #{username}!")
      |> redirect(to: ~p"/poker/#{poker_id}/live")
    else
      conn = delete_session(conn, "poker_#{poker_id}")
      attempt_user_join(conn, poker, username, changeset, poker_id)
    end
  end

  defp attempt_user_join(conn, poker, username, changeset, poker_id) do
    case Poker.join_poker_user(poker, username) do
      {:ok, token} ->
        conn
        |> put_session("poker_#{poker_id}", %{
          "username" => username,
          "token" => token,
          "poker_id" => poker_id
        })
        |> put_flash(:info, "Welcome, #{username}!")
        |> redirect(to: ~p"/poker/#{poker_id}/live")

      {:error, :username_taken} ->
        changeset_with_error =
          changeset
          |> Ecto.Changeset.add_error(:name, "is already taken")

        conn
        |> put_flash(:error, "Username is already taken")
        |> render_join_form(poker, to_form(changeset_with_error))

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to join poker")
        |> render_join_form(poker)
    end
  end

  def leave(conn, %{"id" => poker_id}) do
    # Clear session
    conn = delete_session(conn, "poker_#{poker_id}")

    conn
    |> put_flash(:info, "You have left the poker session")
    |> redirect(to: ~p"/")
  end

  def join_creator(conn, %{"id" => poker_id, "username" => username, "token" => token}) do
    # Special route for poker creators - sets up their session
    conn
    |> put_session("poker_#{poker_id}", %{
      "username" => username,
      "token" => token,
      "poker_id" => poker_id
    })
    |> redirect(to: ~p"/poker/#{poker_id}/live")
  end

  defp render_join_form(conn, poker, form \\ nil) do
    form = form || to_form(JoinPokerForm.changeset(%JoinPokerForm{}))

    render(conn, :join,
      page_title: "Join #{poker.name}",
      poker: poker,
      form: form
    )
  end

  defp valid_uuid?(uuid_string) do
    case Ecto.UUID.cast(uuid_string) do
      {:ok, _} -> true
      :error -> false
    end
  end
end
