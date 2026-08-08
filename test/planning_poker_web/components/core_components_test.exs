defmodule PlanningPokerWeb.CoreComponentsTest do
  use PlanningPokerWeb.ConnCase, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import PlanningPokerWeb.CoreComponents

  alias Phoenix.LiveView.JS
  alias PlanningPokerWeb.CoreComponents

  describe "flash/1" do
    test "renders an info flash with title and message" do
      html =
        render_component(&flash/1, %{
          kind: :info,
          title: "Success",
          flash: %{"info" => "It worked!"}
        })

      assert html =~ "Success"
      assert html =~ "It worked!"
      assert html =~ "alert-info"
    end

    test "renders an error flash" do
      html = render_component(&flash/1, %{kind: :error, flash: %{"error" => "Boom"}})

      assert html =~ "Boom"
      assert html =~ "alert-error"
    end
  end

  describe "button/1" do
    defp button_example(assigns) do
      ~H"""
      <.button type="submit">Save</.button>
      """
    end

    defp button_variant_example(assigns) do
      ~H"""
      <.button variant="primary">Go</.button>
      """
    end

    defp button_link_example(assigns) do
      ~H"""
      <.button navigate="/poker">To the poker</.button>
      """
    end

    test "renders a submit button" do
      html = render_component(&button_example/1, %{})

      assert html =~ "<button"
      assert html =~ ~s(type="submit")
      assert html =~ "Save"
      assert html =~ "btn-primary btn-soft"
    end

    test "renders the primary variant" do
      html = render_component(&button_variant_example/1, %{})
      assert html =~ "btn-primary"
      refute html =~ "btn-soft"
    end

    test "renders a link when navigate is given" do
      html = render_component(&button_link_example/1, %{})

      assert html =~ "<a"
      assert html =~ ~s(href="/poker")
      assert html =~ "To the poker"
    end
  end

  describe "header/1" do
    defp header_example(assigns) do
      ~H"""
      <.header>
        The Title
        <:subtitle>The subtitle</:subtitle>
        <:actions><button type="button">Act</button></:actions>
      </.header>
      """
    end

    test "renders title, subtitle and actions" do
      html = render_component(&header_example/1, %{})

      assert html =~ "The Title"
      assert html =~ "The subtitle"
      assert html =~ "Act"
      assert html =~ "flex items-center justify-between gap-6"
    end
  end

  describe "table/1" do
    defp table_example(assigns) do
      assigns = assign(assigns, rows: [%{name: "alice"}, %{name: "bob"}])

      ~H"""
      <.table id="users" rows={@rows}>
        <:col :let={user} label="Name">{user.name}</:col>
        <:action :let={_user}><button type="button">edit</button></:action>
      </.table>
      """
    end

    test "renders rows with columns and actions" do
      html = render_component(&table_example/1, %{})

      assert html =~ ~s(id="users")
      assert html =~ "Name"
      assert html =~ "alice"
      assert html =~ "bob"
      assert html =~ "edit"
      assert html =~ "Actions"
    end
  end

  describe "list/1" do
    defp list_example(assigns) do
      ~H"""
      <.list>
        <:item title="Title A">Value A</:item>
        <:item title="Title B">Value B</:item>
      </.list>
      """
    end

    test "renders items with titles" do
      html = render_component(&list_example/1, %{})

      assert html =~ "Title A"
      assert html =~ "Value A"
      assert html =~ "Title B"
      assert html =~ "Value B"
    end
  end

  describe "icon/1" do
    test "renders a heroicon span" do
      html = render_component(&icon/1, %{name: "hero-x-mark"})

      assert html =~ "hero-x-mark"
      assert html =~ "size-4"
    end

    test "accepts custom classes" do
      html = render_component(&icon/1, %{name: "hero-x-mark", class: "size-8 text-red-500"})
      assert html =~ "size-8 text-red-500"
    end
  end

  describe "input/1" do
    test "renders a text input with label and value" do
      html =
        render_component(&input/1, %{
          type: "text",
          name: "email",
          id: "email",
          label: "Email",
          value: "a@b.c"
        })

      assert html =~ ~s(type="text")
      assert html =~ "Email"
      assert html =~ ~s(value="a@b.c")
    end

    test "renders a checkbox" do
      html =
        render_component(&input/1, %{
          type: "checkbox",
          name: "agree",
          id: "agree",
          label: "Agree",
          checked: true
        })

      assert html =~ ~s(type="checkbox")
      assert html =~ "checked"
      assert html =~ ~s(type="hidden")
    end

    test "renders a select with options and prompt" do
      html =
        render_component(&input/1, %{
          type: "select",
          name: "card_type",
          id: "card_type",
          label: "Card Type",
          options: [{"Fibonacci", "fibonacci"}],
          prompt: "Choose one",
          value: "fibonacci"
        })

      assert html =~ "<select"
      assert html =~ "Choose one"
      assert html =~ "Fibonacci"
      assert html =~ "selected"
    end

    test "renders a textarea" do
      html =
        render_component(&input/1, %{
          type: "textarea",
          name: "notes",
          id: "notes",
          label: "Notes",
          value: "hello"
        })

      assert html =~ "<textarea"
      assert html =~ "hello"
    end

    test "renders error messages" do
      html =
        render_component(&input/1, %{
          type: "text",
          name: "name",
          id: "name",
          value: nil,
          errors: ["is invalid"]
        })

      assert html =~ "is invalid"
      assert html =~ "text-error"
    end

    test "renders from a form field" do
      form = Phoenix.Component.to_form(%{"name" => "alice"}, as: :user)

      html = render_component(&input/1, %{field: form[:name], type: "text"})

      assert html =~ ~s(name="user[name]")
      assert html =~ ~s(id="user_name")
      assert html =~ ~s(value="alice")
    end
  end

  describe "show/2 and hide/2" do
    test "build JS commands" do
      show_js = show("#modal")
      assert %JS{} = show_js

      combined = hide(show_js, "#modal")
      assert %JS{} = combined

      encoded = Jason.encode!(combined)
      assert encoded =~ "show"
      assert encoded =~ "hide"
    end
  end

  describe "error translation" do
    test "translate_error/1 returns the message" do
      assert CoreComponents.translate_error({"can't be blank", []}) == "can't be blank"
    end

    test "translate_errors/2 filters errors by field" do
      errors = [name: {"can't be blank", []}, title: {"is invalid", []}]

      assert CoreComponents.translate_errors(errors, :name) == ["can't be blank"]
      assert CoreComponents.translate_errors(errors, :title) == ["is invalid"]
    end
  end
end
