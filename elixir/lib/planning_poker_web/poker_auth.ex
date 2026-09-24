defmodule PlanningPokerWeb.PokerAuth do
  @moduledoc """
  Authentication plug for poker sessions.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias PlanningPoker.Poker

  def on_mount(:ensure_authenticated, %{"id" => poker_id}, session, socket) do
    if valid_uuid?(poker_id) do
      authenticate_with_poker(poker_id, session, socket)
    else
      # Invalid UUID - redirect to controller route which will show 404
      {:halt, socket |> push_navigate(to: "/poker/#{poker_id}")}
    end
  end

  def on_mount(:ensure_authenticated, _params, _session, socket) do
    {:halt,
     socket
     |> put_flash(:error, "Session not found.")
     |> push_navigate(to: "/")}
  end

  defp authenticate_with_poker(poker_id, session, socket) do
    case Poker.get_poker(poker_id) do
      nil ->
        # Poker doesn't exist - redirect to controller route which will show 404
        {:halt, socket |> push_navigate(to: "/poker/#{poker_id}")}

      poker ->
        authenticate_user_session(poker, poker_id, session, socket)
    end
  end

  defp authenticate_user_session(poker, poker_id, session, socket) do
    session_key = "poker_#{poker_id}"

    case session[session_key] do
      %{"username" => username, "poker_id" => session_poker_id}
      when is_binary(username) and session_poker_id == poker_id ->
        validate_user_membership(poker, username, poker_id, socket)

      _ ->
        redirect_to_join(socket, poker_id, "Please join the session first.")
    end
  end

  defp validate_user_membership(poker, username, poker_id, socket) do
    if username in (poker.usernames || []) do
      {:cont, socket |> assign(:current_user, username) |> assign(:poker_id, poker_id)}
    else
      redirect_to_join(
        socket,
        poker_id,
        "You are no longer part of this session. Please join again."
      )
    end
  end

  defp redirect_to_join(socket, poker_id, message) do
    {:halt,
     socket
     |> put_flash(:error, message)
     |> push_navigate(to: "/poker/#{poker_id}")}
  end

  defp valid_uuid?(uuid_string) do
    case Ecto.UUID.cast(uuid_string) do
      {:ok, _} -> true
      :error -> false
    end
  end
end
