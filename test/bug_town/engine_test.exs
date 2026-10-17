defmodule BugTown.EngineTest do
  use BugTown.DataCase, async: false
  alias BugTown.Engine.Coordinator
  alias BugTown.Engine.Scenarios

  setup do
    # Ensure baseline simulation state is clean before each test
    Coordinator.reset_sim()
    :ok
  end

  test "coordinator initializes with 10 services and steady-state metrics" do
    state = Coordinator.get_state()
    assert map_size(state.services) == 10
    assert length(state.dependencies) == 11
    assert state.status == :running
    assert state.global_metrics.health_pct >= 90.0
    assert state.global_metrics.total_rps > 0.0

    # Verify key services are present
    assert Map.has_key?(state.services, "api-gateway")
    assert Map.has_key?(state.services, "auth-service")
    assert Map.has_key?(state.services, "user-service")
    assert Map.has_key?(state.services, "order-service")
    assert Map.has_key?(state.services, "payment-service")
    assert Map.has_key?(state.services, "postgres-db")
  end

  test "memory leak degrades service memory and spawns a living bug entity" do
    {:ok, fault} =
      Coordinator.inject_fault("memory_leak", "user-service", %{
        "growth_rate_mb" => 50,
        "max_memory_mb" => 500
      })

    assert fault.type == "memory_leak"
    assert fault.target == "user-service"

    # Allow simulation ticks to execute
    send(Process.whereis(Coordinator), :tick)
    send(Process.whereis(Coordinator), :tick)
    send(Process.whereis(Coordinator), :tick)

    state = Coordinator.get_state()
    user_svc = Map.get(state.services, "user-service")
    assert user_svc.memory_mb > user_svc.baseline_memory_mb

    # Verify living bug was spawned
    assert map_size(state.bugs) >= 1
    {_id, bug} = Enum.find(state.bugs, fn {_id, b} -> b.originating_fault_id == fault.id end)
    assert bug != nil
    assert bug.type == "memory_hog"
    assert bug.current_service == "user-service"
    assert bug.status in ["spawned", "active", "propagating"]

    # Apply recovery
    {:ok, recovery} = Coordinator.apply_recovery("restart", "user-service")
    assert recovery.success == true

    # Tick to let recovery take effect
    send(Process.whereis(Coordinator), :tick)

    post_state = Coordinator.get_state()
    recovered_user_svc = Map.get(post_state.services, "user-service")
    assert recovered_user_svc.status == "healthy"
    assert recovered_user_svc.memory_mb == recovered_user_svc.baseline_memory_mb
  end

  test "service crash marks target offline and creates an incident" do
    {:ok, _fault} =
      Coordinator.inject_fault("service_crash", "payment-service", %{"crash_mode" => "sigkill"})

    send(Process.whereis(Coordinator), :tick)
    send(Process.whereis(Coordinator), :tick)

    state = Coordinator.get_state()
    payment_svc = Map.get(state.services, "payment-service")
    assert payment_svc.status == "offline"
    assert payment_svc.error_rate == 1.0

    # Verify incident was created and deduplicated
    assert map_size(state.incidents) >= 1

    incident =
      Enum.find_value(state.incidents, fn {_id, inc} ->
        if "payment-service" in inc.affected_services, do: inc, else: nil
      end)

    assert incident != nil
    assert incident.status in ["open", "investigating"]

    # Restart payment service
    {:ok, _rec} = Coordinator.apply_recovery("restart", "payment-service")
    send(Process.whereis(Coordinator), :tick)

    new_state = Coordinator.get_state()
    recovered_pay = Map.get(new_state.services, "payment-service")
    assert recovered_pay.status in ["healthy", "recovering"]
  end

  test "circuit breaker recovery halts cascading propagation" do
    {:ok, _fault} =
      Coordinator.inject_fault("database_failure", "postgres-db", %{
        "mode" => "connection_failure"
      })

    send(Process.whereis(Coordinator), :tick)
    send(Process.whereis(Coordinator), :tick)

    # Apply circuit breaker on order service
    {:ok, rec} = Coordinator.apply_recovery("circuit_breaker", "order-service")
    assert rec.success == true

    send(Process.whereis(Coordinator), :tick)
    state = Coordinator.get_state()
    order_svc = Map.get(state.services, "order-service")
    assert order_svc.error_rate <= 0.05
  end

  test "simulation lifecycle controls: pause, resume, reset, speed" do
    assert {:ok, paused_state} = Coordinator.pause_sim()
    assert paused_state.status == :paused

    assert {:ok, resumed_state} = Coordinator.resume_sim()
    assert resumed_state.status == :running

    assert {:ok, speed_state} = Coordinator.set_speed(2.0)
    assert speed_state.speed == 2.0

    assert {:ok, reset_state} = Coordinator.reset_sim()
    assert reset_state.active_faults == %{}
    assert reset_state.bugs == %{}
  end

  test "scenarios repository returns valid built-in scenarios" do
    scenarios = Scenarios.all()
    assert length(scenarios) == 8

    scen = Scenarios.get("memory_leak_exhaustion")
    assert scen != nil
    assert scen.fault_type == "memory_leak"

    {:ok, launched} = Coordinator.run_scenario("memory_leak_exhaustion")
    assert launched.id == "memory_leak_exhaustion"

    state = Coordinator.get_state()
    assert map_size(state.active_faults) == 1
    assert state.current_experiment != nil
  end
end
