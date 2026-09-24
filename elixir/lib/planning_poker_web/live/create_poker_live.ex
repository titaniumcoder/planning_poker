defmodule PlanningPokerWeb.CreatePokerLive do
  use PlanningPokerWeb, :live_view

  alias PlanningPoker.Poker
  alias PlanningPokerWeb.Forms.CreatePokerForm

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    case params do
      %{} ->
        handle_create_poker(socket)
    end
  end

  def handle_event(
        "validate",
        %{"create_poker_form" => form_params},
        socket
      ) do
    changeset =
      %CreatePokerForm{}
      |> CreatePokerForm.changeset(form_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("create_poker", %{"create_poker_form" => form_params}, socket) do
    changeset = CreatePokerForm.changeset(%CreatePokerForm{}, form_params)

    case changeset.valid? do
      true -> handle_valid_poker_creation(changeset, socket)
      false -> {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("redirect_to_join", %{"poker_id" => poker_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/poker/#{poker_id}")}
  end

  # Private helper functions
  defp handle_create_poker(socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Create Poker")
     |> assign(:mode, :create)
     |> assign(:form, to_form(CreatePokerForm.changeset(%CreatePokerForm{})))}
  end

  defp handle_valid_poker_creation(changeset, socket) do
    data = Ecto.Changeset.apply_changes(changeset)

    with {:ok, poker} <- Poker.create_poker(%{name: data.name, card_type: data.card_type}),
         {:ok, token} <- Poker.join_poker_user(poker, data.username) do
      {:noreply,
       socket
       |> put_flash(:info, "Poker session created successfully!")
       |> push_navigate(to: ~p"/poker/#{poker.id}/creator/#{data.username}/#{token}")}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create poker session")}
    end
  end
end
