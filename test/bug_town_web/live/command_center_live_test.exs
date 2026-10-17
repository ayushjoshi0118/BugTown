defmodule BugTownWeb.CommandCenterLiveTest do
  use BugTownWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias BugTown.Engine.Coordinator

  setup do
    Coordinator.reset_sim()
    :ok
  end

  test "loads command center and renders living topology nodes", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "SYSTEM COMMAND CENTER"
    assert html =~ "API Gateway"
    assert html =~ "PostgreSQL Database"
    assert html =~ "User Service"
    assert html =~ "Order Service"

    # Test selecting a service opens the inspector drawer
    rendered =
      view
      |> element("g[phx-click='select_service'][phx-value-slug='user-service']")
      |> render_click()

    assert rendered =~ "Slug: user-service"
    assert rendered =~ "Restart Service"
    assert rendered =~ "Enable Circuit Breaker"
  end

  test "quick fault button injects fault and triggers live update", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Click Leak Memory
    view
    |> element("button[phx-click='quick_fault'][phx-value-type='memory_leak']")
    |> render_click()

    state = Coordinator.get_state()
    assert map_size(state.active_faults) >= 1

    # Allow a tick so living bug spawns
    send(Process.whereis(Coordinator), :tick)
    send(Process.whereis(Coordinator), :tick)

    updated_html = render(view)
    assert updated_html =~ "BUG-" or updated_html =~ "Living Bugs"
  end

  test "sim controls: pause and resume work from UI", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("button[phx-click='pause_sim']")
    |> render_click()

    assert Coordinator.get_state().status == :paused

    view
    |> element("button[phx-click='resume_sim']")
    |> render_click()

    assert Coordinator.get_state().status == :running
  end
end
