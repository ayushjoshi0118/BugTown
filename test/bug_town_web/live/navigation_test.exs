defmodule BugTownWeb.NavigationTest do
  use BugTownWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias BugTown.Engine.Coordinator

  setup do
    Coordinator.reset_sim()
    :ok
  end

  test "navigation to Topology Explorer renders dependency graph", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/topology")
    assert html =~ "TOPOLOGY EXPLORER"
    assert html =~ "Interactive distributed dependency architecture"
    assert html =~ "Traffic:"

    # Clicking a node opens inspector
    inspected =
      view
      |> element("g[phx-click='select_node'][phx-value-slug='postgres-db']")
      |> render_click()

    assert inspected =~ "Node Inspector"
    assert inspected =~ "PostgreSQL Database"
  end

  test "navigation to Fault Injection Lab renders vectors and form", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/faults")
    assert html =~ "FAULT INJECTION LAB"
    assert html =~ "Memory Leak"
    assert html =~ "Service Crash"
    assert html =~ "Database Outage"
    assert html =~ "Inject Fault Into Runtime"

    # Injecting a fault via the Fault Lab form
    view
    |> form("form[phx-submit='inject_fault']", %{
      "target_service" => "order-service",
      "severity" => "high",
      "duration_ticks" => "40"
    })
    |> render_submit()

    state = Coordinator.get_state()
    assert Enum.any?(state.active_faults, fn {_id, f} -> f.target == "order-service" end)
  end

  test "navigation to Incidents renders incident management console", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/incidents")
    assert html =~ "INCIDENT MANAGEMENT &amp; ROOT CAUSE CORRELATION"
    assert html =~ "Incident Register"
  end

  test "navigation to Observability renders metrics, logs, and traces", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/observability")
    assert html =~ "SIMULATED OBSERVABILITY SUITE"
    assert html =~ "Request Latency"
    assert html =~ "System Throughput"

    # Switch to logs tab
    logs_html =
      view
      |> element("button[phx-click='set_tab'][phx-value-tab='logs']")
      |> render_click()

    assert logs_html =~ "Search log messages"

    # Switch to traces tab
    traces_html =
      view
      |> element("button[phx-click='set_tab'][phx-value-tab='traces']")
      |> render_click()

    assert traces_html =~ "Recent Request Traces"
  end

  test "navigation to Experiments renders chaos scenario catalog", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/experiments")
    assert html =~ "CHAOS EXPERIMENTS &amp; REPLAY STUDIO"
    assert html =~ "Memory Leak Causing Service Exhaustion"
    assert html =~ "Database Outage Causing Cascading Failures"
    assert html =~ "Circuit Breaker Preventing Cascading Failures"

    # Launch a scenario
    view
    |> element("button[phx-click='launch_scenario'][phx-value-id='database_cascading_failure']")
    |> render_click()

    state = Coordinator.get_state()
    assert state.current_experiment != nil
    assert state.current_experiment.scenario_type == "database_cascading_failure"
  end

  test "navigation to Recovery Center renders mitigations and active shields", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/recovery")
    assert html =~ "RECOVERY CENTER &amp; RESILIENCE MITIGATIONS"
    assert html =~ "Restart Service"
    assert html =~ "Enable Circuit Breaker"
    assert html =~ "Deploy Recovery Mitigation"

    # Deploy a mitigation
    view
    |> element("button[phx-click='execute_recovery']")
    |> render_click()

    state = Coordinator.get_state()
    assert map_size(state.active_recoveries) >= 1
  end

  test "navigation to Settings renders engine thresholds and speed controls", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/settings")
    assert html =~ "SIMULATOR CONFIGURATION &amp; ENGINE THRESHOLDS"
    assert html =~ "Simulation Speed Multiplier"
    assert html =~ "Incident Trigger Thresholds"

    # Adjust speed to 2x
    view
    |> element("button[phx-click='speed_change'][phx-value-speed='2.0']")
    |> render_click()

    state = Coordinator.get_state()
    assert state.speed == 2.0
  end
end
