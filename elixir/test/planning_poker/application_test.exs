defmodule PlanningPoker.ApplicationTest do
  use ExUnit.Case, async: true

  test "config_change/3 updates the endpoint configuration" do
    assert :ok = PlanningPoker.Application.config_change([], [], [])
  end
end
