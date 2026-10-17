defmodule BugTown.Engine.Coordinator do
  @moduledoc """
  The central OTP GenServer orchestrating the live software simulation engine.
  Manages ticking, state transitions, PubSub broadcasts, faults, living bugs,
  recoveries, and observability streams.
  """

  use GenServer

  alias BugTown.Engine.{
    State,
    FaultEvaluator,
    BugPropagator,
    TrafficSimulator,
    IncidentManager,
    Scenarios
  }

  alias BugTown.Repo
  alias BugTown.Topology.{Service, ServiceDependency}
  alias BugTown.Faults.Fault
  alias BugTown.Recoveries.RecoveryAction
  alias BugTown.Experiments.Experiment
  alias BugTown.Observability.MetricSample

  @pubsub_topic "simulation:state"
  @default_tick_ms 800

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the authoritative simulation state."
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc "Starts the simulation if stopped."
  def start_sim do
    GenServer.call(__MODULE__, :start_sim)
  end

  @doc "Pauses the simulation."
  def pause_sim do
    GenServer.call(__MODULE__, :pause_sim)
  end

  @doc "Resumes the simulation if paused."
  def resume_sim do
    GenServer.call(__MODULE__, :resume_sim)
  end

  @doc "Resets all services, faults, bugs, and traffic to steady baseline state."
  def reset_sim do
    GenServer.call(__MODULE__, :reset_sim)
  end

  @doc "Adjusts simulation speed multiplier (0.5, 1.0, 2.0, 5.0)."
  def set_speed(speed) when is_number(speed) and speed > 0 do
    GenServer.call(__MODULE__, {:set_speed, speed})
  end

  @doc "Injects a fault into the running simulation."
  def inject_fault(type, target, params \\ %{}, severity \\ "high", duration_ticks \\ 60) do
    GenServer.call(__MODULE__, {:inject_fault, type, target, params, severity, duration_ticks})
  end

  @doc "Removes or mitigates an active fault."
  def remove_fault(fault_id) do
    GenServer.call(__MODULE__, {:remove_fault, fault_id})
  end

  @doc "Applies a recovery mechanism against a service or system."
  def apply_recovery(action_type, target, params \\ %{}) do
    GenServer.call(__MODULE__, {:apply_recovery, action_type, target, params})
  end

  @doc "Runs a pre-configured chaos experiment scenario."
  def run_scenario(scenario_id, opts \\ %{}) do
    GenServer.call(__MODULE__, {:run_scenario, scenario_id, opts})
  end

  @doc "Acknowledges an incident and optionally adds notes."
  def acknowledge_incident(incident_id, notes \\ "") do
    GenServer.call(__MODULE__, {:acknowledge_incident, incident_id, notes})
  end

  @doc "Saves current experiment state into PostgreSQL."
  def save_current_experiment(name, scenario_type, description \\ "") do
    GenServer.call(__MODULE__, {:save_current_experiment, name, scenario_type, description})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Load initial service graph from DB (or fallback if not yet migrated)
    {services, dependencies} = load_topology_from_db()

    initial_state = %State{
      status: :running,
      tick_count: 0,
      speed: 1.0,
      sim_time_seconds: 0,
      seed: 42,
      services: services,
      dependencies: dependencies,
      active_faults: %{},
      active_recoveries: %{},
      bugs: %{},
      traffic_packets: [],
      incidents: %{},
      history_metrics: [],
      recent_logs: [
        %{
          timestamp: DateTime.utc_now(),
          severity: "info",
          service_name: "API Gateway",
          event_type: "engine_started",
          correlation_id: "BOOT-001",
          message: "BugTown simulation engine initialized with 10 services and 11 dependencies."
        }
      ],
      recent_traces: [],
      current_experiment: nil
    }

    # Compute baseline metrics
    initial_metrics = TrafficSimulator.step_traffic(services, dependencies, [], 0) |> elem(1)
    state = %{initial_state | global_metrics: initial_metrics}

    timer_ref = schedule_next_tick(state.speed)

    {:ok, %{state: state, timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:get_state, _from, %{state: state} = server_state) do
    {:reply, state, server_state}
  end

  @impl true
  def handle_call(:start_sim, _from, %{state: state, timer_ref: timer_ref} = server_state) do
    cancel_timer(timer_ref)
    new_state = %{state | status: :running}
    new_timer = schedule_next_tick(new_state.speed)
    broadcast_state(new_state)
    {:reply, {:ok, new_state}, %{server_state | state: new_state, timer_ref: new_timer}}
  end

  @impl true
  def handle_call(:pause_sim, _from, %{state: state, timer_ref: timer_ref} = server_state) do
    cancel_timer(timer_ref)
    new_state = %{state | status: :paused}
    broadcast_state(new_state)
    {:reply, {:ok, new_state}, %{server_state | state: new_state, timer_ref: nil}}
  end

  @impl true
  def handle_call(:resume_sim, _from, %{state: state, timer_ref: timer_ref} = server_state) do
    cancel_timer(timer_ref)
    new_state = %{state | status: :running}
    new_timer = schedule_next_tick(new_state.speed)
    broadcast_state(new_state)
    {:reply, {:ok, new_state}, %{server_state | state: new_state, timer_ref: new_timer}}
  end

  @impl true
  def handle_call(:reset_sim, _from, %{state: state} = server_state) do
    {fresh_services, deps} = load_topology_from_db()

    reset_state = %{
      state
      | services: fresh_services,
        dependencies: deps,
        active_faults: %{},
        active_recoveries: %{},
        bugs: %{},
        traffic_packets: [],
        incidents: %{},
        current_experiment: nil
    }

    log = %{
      timestamp: DateTime.utc_now(),
      severity: "info",
      service_name: "system",
      event_type: "simulation_reset",
      correlation_id: "RST-#{state.tick_count}",
      message: "Simulation reset to pristine baseline state. All faults and bugs cleared."
    }

    new_state = %{reset_state | recent_logs: [log | Enum.take(state.recent_logs, 25)]}
    broadcast_state(new_state)
    {:reply, {:ok, new_state}, %{server_state | state: new_state}}
  end

  @impl true
  def handle_call(
        {:set_speed, speed},
        _from,
        %{state: state, timer_ref: timer_ref} = server_state
      ) do
    cancel_timer(timer_ref)
    new_state = %{state | speed: speed}
    new_timer = if new_state.status == :running, do: schedule_next_tick(speed), else: nil
    broadcast_state(new_state)
    {:reply, {:ok, new_state}, %{server_state | state: new_state, timer_ref: new_timer}}
  end

  @impl true
  def handle_call(
        {:inject_fault, type, target, params, severity, duration_ticks},
        _from,
        %{state: state} = server_state
      ) do
    fault_id = "flt-#{:erlang.phash2({type, target, state.tick_count}, 9000) + 1000}"

    fault = %{
      id: fault_id,
      type: to_string(type),
      target: to_string(target),
      params: params,
      severity: to_string(severity),
      injected_at_tick: state.tick_count,
      duration_ticks: duration_ticks,
      status: "active"
    }

    # Persist in DB asynchronously so we don't stall the sim
    spawn(fn ->
      persist_fault_record(fault)
    end)

    log = %{
      timestamp: DateTime.utc_now(),
      severity: "warn",
      service_name: target,
      event_type: "fault_injected",
      correlation_id: fault_id,
      message:
        "Injected fault #{type} into #{target} (severity: #{severity}, duration: #{duration_ticks} ticks)."
    }

    updated_faults = Map.put(state.active_faults, fault_id, fault)

    new_state = %{
      state
      | active_faults: updated_faults,
        recent_logs: [log | Enum.take(state.recent_logs, 40)]
    }

    broadcast_state(new_state)
    {:reply, {:ok, fault}, %{server_state | state: new_state}}
  end

  @impl true
  def handle_call({:remove_fault, fault_id}, _from, %{state: state} = server_state) do
    case Map.get(state.active_faults, fault_id) do
      nil ->
        {:reply, {:error, :not_found}, server_state}

      fault ->
        updated_faults = Map.delete(state.active_faults, fault_id)

        log = %{
          timestamp: DateTime.utc_now(),
          severity: "info",
          service_name: fault.target || "system",
          event_type: "fault_removed",
          correlation_id: fault_id,
          message: "Fault #{fault.type} manually removed from #{fault.target}."
        }

        # Also trigger target service recovery toward baseline
        target_slug = fault.target

        updated_services =
          case Map.get(state.services, target_slug) do
            nil ->
              state.services

            svc ->
              recovered = %{
                svc
                | status: "healthy",
                  error_rate: svc.baseline_error_rate,
                  latency_ms: svc.baseline_latency_ms,
                  cpu_pct: svc.baseline_cpu,
                  memory_mb: svc.baseline_memory_mb,
                  active_faults_count: max(0, svc.active_faults_count - 1)
              }

              Map.put(state.services, target_slug, recovered)
          end

        new_state = %{
          state
          | active_faults: updated_faults,
            services: updated_services,
            recent_logs: [log | Enum.take(state.recent_logs, 40)]
        }

        broadcast_state(new_state)
        {:reply, {:ok, fault}, %{server_state | state: new_state}}
    end
  end

  @impl true
  def handle_call(
        {:apply_recovery, action_type, target, params},
        _from,
        %{state: state} = server_state
      ) do
    rec_id = "rec-#{:rand.uniform(9000) + 1000}"
    target_slug = to_string(target)
    action_str = to_string(action_type)

    metrics_before = state.global_metrics

    # Immediate simulation reaction based on action type
    {updated_services, updated_faults, success, details} =
      execute_recovery_action(
        action_str,
        target_slug,
        params,
        state.services,
        state.active_faults
      )

    recovery = %{
      id: rec_id,
      type: action_str,
      target: target_slug,
      params: params,
      status: "applied",
      applied_at_tick: state.tick_count,
      applied_at: DateTime.utc_now(),
      metrics_before: metrics_before,
      success: success,
      details: details
    }

    log = %{
      timestamp: DateTime.utc_now(),
      severity: if(success, do: "info", else: "warn"),
      service_name: target_slug,
      event_type: "recovery_applied",
      correlation_id: rec_id,
      message: "Applied recovery: #{action_str} on #{target_slug}. Result: #{details}"
    }

    # Persist in DB
    spawn(fn ->
      persist_recovery_record(recovery)
    end)

    new_state = %{
      state
      | services: updated_services,
        active_faults: updated_faults,
        active_recoveries: Map.put(state.active_recoveries, rec_id, recovery),
        recent_logs: [log | Enum.take(state.recent_logs, 40)]
    }

    broadcast_state(new_state)
    {:reply, {:ok, recovery}, %{server_state | state: new_state}}
  end

  @impl true
  def handle_call({:run_scenario, scenario_id, opts}, _from, %{state: state} = server_state) do
    scenario = Scenarios.get(to_string(scenario_id))

    if scenario do
      # 1. Reset baseline
      {fresh_services, deps} = load_topology_from_db()

      # 2. Inject the scenario's defined fault
      fault_id = "flt-scen-#{scenario.id}-#{state.tick_count}"

      fault = %{
        id: fault_id,
        type: scenario.fault_type,
        target: scenario.target_service,
        params: scenario.fault_params,
        severity: "high",
        injected_at_tick: state.tick_count,
        duration_ticks: Map.get(scenario.fault_params, "duration_ticks", 60),
        status: "active"
      }

      experiment = %{
        name: scenario.name,
        scenario_type: scenario.id,
        description: scenario.description,
        seed: Map.get(opts, :seed, 42),
        started_at_tick: state.tick_count,
        baseline_metrics: state.global_metrics
      }

      log = %{
        timestamp: DateTime.utc_now(),
        severity: "info",
        service_name: scenario.target_service,
        event_type: "scenario_started",
        correlation_id: scenario.id,
        message: "Started Chaos Scenario: #{scenario.name}. Target: #{scenario.target_service}"
      }

      new_state = %{
        state
        | services: fresh_services,
          dependencies: deps,
          active_faults: %{fault_id => fault},
          active_recoveries: %{},
          bugs: %{},
          incidents: %{},
          traffic_packets: [],
          current_experiment: experiment,
          recent_logs: [log | Enum.take(state.recent_logs, 30)]
      }

      broadcast_state(new_state)
      {:reply, {:ok, scenario}, %{server_state | state: new_state}}
    else
      {:reply, {:error, :scenario_not_found}, server_state}
    end
  end

  @impl true
  def handle_call(
        {:acknowledge_incident, incident_id, notes},
        _from,
        %{state: state} = server_state
      ) do
    case Map.get(state.incidents, incident_id) do
      nil ->
        {:reply, {:error, :not_found}, server_state}

      incident ->
        updated = %{
          incident
          | status: "investigating",
            notes: notes,
            acknowledged_at: DateTime.utc_now(),
            timeline_events: [
              %{
                tick: state.tick_count,
                timestamp: DateTime.utc_now(),
                event: "Incident acknowledged by engineer. Investigation notes attached."
              }
              | incident.timeline_events
            ]
        }

        new_state = %{state | incidents: Map.put(state.incidents, incident_id, updated)}
        broadcast_state(new_state)
        {:reply, {:ok, updated}, %{server_state | state: new_state}}
    end
  end

  @impl true
  def handle_call(
        {:save_current_experiment, name, scenario_type, description},
        _from,
        %{state: state} = server_state
      ) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    record =
      %Experiment{}
      |> Experiment.changeset(%{
        name: name,
        scenario_type: scenario_type,
        description: description,
        seed: state.seed,
        status: "completed",
        fault_config: state.active_faults,
        recovery_config: state.active_recoveries,
        metrics_summary: %{
          "health_pct" => state.global_metrics.health_pct,
          "total_rps" => state.global_metrics.total_rps,
          "avg_latency_ms" => state.global_metrics.avg_latency_ms,
          "p95_latency_ms" => state.global_metrics.p95_latency_ms,
          "error_rate" => state.global_metrics.error_rate,
          "active_bugs_count" => map_size(state.bugs),
          "active_incidents_count" => map_size(state.incidents)
        },
        duration_seconds: max(10, state.tick_count),
        started_at: DateTime.add(now, -60, :second),
        completed_at: now
      })

    case Repo.insert(record) do
      {:ok, saved} ->
        log = %{
          timestamp: DateTime.utc_now(),
          severity: "info",
          service_name: "system",
          event_type: "experiment_saved",
          correlation_id: "EXP-#{saved.id}",
          message: "Saved experiment '#{name}' (ID: #{saved.id}) with recorded metrics snapshot."
        }

        new_state = %{state | recent_logs: [log | Enum.take(state.recent_logs, 40)]}
        broadcast_state(new_state)
        {:reply, {:ok, saved}, %{server_state | state: new_state}}

      {:error, changeset} ->
        {:reply, {:error, changeset}, server_state}
    end
  end

  @impl true
  def handle_info(:tick, %{state: %{status: :paused}} = server_state) do
    # Simulation is paused, do not advance state
    {:noreply, server_state}
  end

  @impl true
  def handle_info(:tick, %{state: state} = server_state) do
    new_tick = state.tick_count + 1
    new_sim_time = state.sim_time_seconds + 1

    # 1. Evaluate Faults
    {services, active_faults, fault_logs} =
      FaultEvaluator.evaluate_faults(
        state.services,
        state.dependencies,
        state.active_faults,
        state.active_recoveries,
        new_tick
      )

    # 2. Step Living Bugs
    {bugs, services, bug_logs} =
      BugPropagator.step_bugs(
        state.bugs,
        services,
        state.dependencies,
        active_faults,
        state.active_recoveries,
        new_tick
      )

    # 3. Simulate Traffic Packets, Metrics, and Distributed Traces
    {packets, global_metrics, new_traces} =
      TrafficSimulator.step_traffic(
        services,
        state.dependencies,
        state.traffic_packets,
        new_tick
      )

    # 4. Evaluate Incidents
    {incidents, incident_logs} =
      IncidentManager.evaluate_incidents(
        state.incidents,
        services,
        active_faults,
        new_tick
      )

    # Combine new logs
    all_new_logs = fault_logs ++ bug_logs ++ incident_logs
    recent_logs = (all_new_logs ++ state.recent_logs) |> Enum.take(50)

    # Update rolling metrics history
    history_metrics = [global_metrics | state.history_metrics] |> Enum.take(60)

    # Update traces history
    recent_traces = (new_traces ++ state.recent_traces) |> Enum.take(20)

    # Count active incidents
    active_inc_count =
      Enum.count(incidents, fn {_id, inc} ->
        inc.status in ["open", "investigating", "mitigating"]
      end)

    global_metrics = Map.put(global_metrics, :active_incidents_count, active_inc_count)

    new_state = %{
      state
      | tick_count: new_tick,
        sim_time_seconds: new_sim_time,
        services: services,
        active_faults: active_faults,
        bugs: bugs,
        traffic_packets: packets,
        global_metrics: global_metrics,
        incidents: incidents,
        history_metrics: history_metrics,
        recent_logs: recent_logs,
        recent_traces: recent_traces
    }

    # Persist periodic sample every 20 ticks
    if rem(new_tick, 20) == 0 do
      spawn(fn ->
        persist_metric_sample(global_metrics)
      end)
    end

    # Broadcast updated state to all connected LiveViews
    broadcast_state(new_state)

    # Reschedule next tick
    new_timer = schedule_next_tick(new_state.speed)

    {:noreply, %{server_state | state: new_state, timer_ref: new_timer}}
  end

  ## Private Helpers

  defp schedule_next_tick(speed) do
    interval = round(@default_tick_ms / max(0.2, speed))
    Process.send_after(self(), :tick, interval)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)

  defp broadcast_state(state) do
    Phoenix.PubSub.broadcast(BugTown.PubSub, @pubsub_topic, {:simulation_state_updated, state})
  end

  defp execute_recovery_action("restart", target_slug, _params, services, active_faults) do
    case Map.get(services, target_slug) do
      nil ->
        {services, active_faults, false, "Target service not found"}

      svc ->
        recovered_svc = %{
          svc
          | status: "healthy",
            cpu_pct: svc.baseline_cpu,
            memory_mb: svc.baseline_memory_mb,
            latency_ms: svc.baseline_latency_ms,
            error_rate: svc.baseline_error_rate,
            active_faults_count: 0
        }

        # Clear active faults on this target
        cleaned_faults =
          Enum.reject(active_faults, fn {_id, f} -> f.target == target_slug end)
          |> Map.new()

        {Map.put(services, target_slug, recovered_svc), cleaned_faults, true,
         "Service restarted and restored to pristine baseline."}
    end
  end

  defp execute_recovery_action(
         "restart_dependents",
         target_slug,
         _params,
         services,
         active_faults
       ) do
    # Restart target and reset all dependent services
    updated_services =
      Enum.map(services, fn {slug, svc} ->
        if slug == target_slug or svc.category in ["service", "worker"] do
          {slug,
           %{
             svc
             | status: "healthy",
               cpu_pct: svc.baseline_cpu,
               memory_mb: svc.baseline_memory_mb,
               latency_ms: svc.baseline_latency_ms,
               error_rate: svc.baseline_error_rate,
               active_faults_count: 0
           }}
        else
          {slug, svc}
        end
      end)
      |> Map.new()

    cleaned_faults =
      Enum.reject(active_faults, fn {_id, f} -> f.target == target_slug end)
      |> Map.new()

    {updated_services, cleaned_faults, true,
     "Restarted #{target_slug} and synchronized all dependent workers."}
  end

  defp execute_recovery_action("circuit_breaker", target_slug, _params, services, active_faults) do
    svc = Map.get(services, target_slug)

    if svc do
      # Breaker isolates failures: error rate drops, latency returns near baseline
      updated_svc = %{
        svc
        | error_rate: min(0.02, svc.error_rate),
          latency_ms: svc.baseline_latency_ms + 10,
          status: "healthy"
      }

      {Map.put(services, target_slug, updated_svc), active_faults, true,
       "Circuit breaker tripped to open/half-open isolation. Cascade halted."}
    else
      {services, active_faults, false, "Unknown target service"}
    end
  end

  defp execute_recovery_action("adjust_timeout", target_slug, _params, services, active_faults) do
    svc = Map.get(services, target_slug)

    if svc do
      updated_svc = %{
        svc
        | latency_ms: min(svc.latency_ms, 120),
          error_rate: min(0.04, svc.error_rate)
      }

      {Map.put(services, target_slug, updated_svc), active_faults, true,
       "Deadline timeouts calibrated to 800ms. Hanging connections reclaimed."}
    else
      {services, active_faults, false, "Unknown target service"}
    end
  end

  defp execute_recovery_action("bounded_retries", target_slug, _params, services, active_faults) do
    svc = Map.get(services, target_slug)

    if svc do
      updated_svc = %{
        svc
        | error_rate: min(0.03, svc.error_rate * 0.15),
          latency_ms: svc.baseline_latency_ms + 25
      }

      {Map.put(services, target_slug, updated_svc), active_faults, true,
       "Bounded retries with exponential backoff active. Dropped packets recovered."}
    else
      {services, active_faults, false, "Unknown target service"}
    end
  end

  defp execute_recovery_action("cache_fallback", target_slug, _params, services, active_faults) do
    # When cache fallback is active, read availability jumps and errors drop
    updated_services =
      Enum.map(services, fn {slug, svc} ->
        if slug in ["user-service", "order-service", target_slug] do
          {slug,
           %{
             svc
             | error_rate: 0.02,
               latency_ms: max(15, svc.baseline_latency_ms),
               status: "healthy"
           }}
        else
          {slug, svc}
        end
      end)
      |> Map.new()

    {updated_services, active_faults, true,
     "Redis stale cache fallback enabled. Upstream queries served from cache."}
  end

  defp execute_recovery_action("race_mitigation", target_slug, _params, services, active_faults) do
    svc = Map.get(services, target_slug)

    if svc do
      updated_svc = %{svc | error_rate: svc.baseline_error_rate, status: "healthy"}

      {Map.put(services, target_slug, updated_svc), active_faults, true,
       "Distributed mutex locking active. Optimistic concurrency collisions eliminated."}
    else
      {services, active_faults, false, "Unknown target service"}
    end
  end

  defp execute_recovery_action("pool_adjustment", target_slug, _params, services, active_faults) do
    svc = Map.get(services, target_slug)

    if svc do
      updated_svc = %{
        svc
        | error_rate: 0.01,
          latency_ms: svc.baseline_latency_ms + 5,
          status: "healthy"
      }

      {Map.put(services, target_slug, updated_svc), active_faults, true,
       "Connection pool expanded to 150. Idle connections recycled."}
    else
      {services, active_faults, false, "Unknown target service"}
    end
  end

  defp execute_recovery_action("remove_fault", target_slug, _params, services, active_faults) do
    cleaned_faults =
      Enum.reject(active_faults, fn {_id, f} -> f.target == target_slug end)
      |> Map.new()

    svc = Map.get(services, target_slug)

    updated_services =
      if svc do
        recovered = %{
          svc
          | status: "healthy",
            error_rate: svc.baseline_error_rate,
            latency_ms: svc.baseline_latency_ms,
            cpu_pct: svc.baseline_cpu,
            memory_mb: svc.baseline_memory_mb,
            active_faults_count: 0
        }

        Map.put(services, target_slug, recovered)
      else
        services
      end

    {updated_services, cleaned_faults, true, "Fault revoked. Normal operating bounds restored."}
  end

  defp execute_recovery_action(other_action, target_slug, _params, services, active_faults) do
    {services, active_faults, true, "Action #{other_action} executed on #{target_slug}."}
  end

  defp load_topology_from_db do
    services =
      try do
        Repo.all(Service)
        |> Enum.map(fn s ->
          {s.slug,
           %{
             id: s.id,
             name: s.name,
             slug: s.slug,
             category: s.category,
             status: s.status || "healthy",
             baseline_latency_ms: s.baseline_latency_ms,
             baseline_error_rate: s.baseline_error_rate,
             baseline_cpu: s.baseline_cpu,
             baseline_memory_mb: s.baseline_memory_mb,
             latency_ms: s.baseline_latency_ms,
             error_rate: s.baseline_error_rate,
             cpu_pct: s.baseline_cpu,
             memory_mb: s.baseline_memory_mb,
             pos_x: s.pos_x,
             pos_y: s.pos_y,
             metadata: s.metadata || %{},
             active_faults_count: 0
           }}
        end)
        |> Map.new()
      rescue
        _ -> %{}
      end

    dependencies =
      try do
        Repo.all(ServiceDependency)
        |> Repo.preload([:source_service, :target_service])
        |> Enum.map(fn dep ->
          %{
            id: dep.id,
            source: dep.source_service.slug,
            target: dep.target_service.slug,
            protocol: dep.protocol,
            latency_ms: dep.latency_ms,
            critical: dep.critical
          }
        end)
      rescue
        _ -> []
      end

    if map_size(services) == 0 do
      # Fallback defaults if DB is temporarily empty
      fallback_topology()
    else
      {services, dependencies}
    end
  end

  defp fallback_topology do
    # Guaranteed initial 10 services in memory
    svcs =
      [
        {"api-gateway", "API Gateway", "gateway", 450, 70, 12, 0.001, 24.5, 320},
        {"auth-service", "Authentication Service", "service", 230, 190, 18, 0.002, 18.2, 256},
        {"order-service", "Order Service", "service", 670, 190, 35, 0.003, 32.0, 480},
        {"user-service", "User Service", "service", 230, 310, 22, 0.001, 16.5, 384},
        {"redis-cache", "Redis Cache", "cache", 70, 310, 2, 0.0001, 8.0, 512},
        {"inventory-service", "Inventory Service", "service", 530, 310, 28, 0.002, 21.0, 340},
        {"payment-service", "Payment Service", "service", 810, 310, 65, 0.004, 29.5, 420},
        {"postgres-db", "PostgreSQL Database", "database", 230, 450, 8, 0.0005, 35.0, 1024},
        {"message-queue", "Message Queue", "queue", 530, 450, 4, 0.0002, 12.0, 512},
        {"notification-worker", "Notification Worker", "worker", 810, 450, 45, 0.005, 14.0, 280}
      ]
      |> Enum.map(fn {slug, name, cat, px, py, lat, err, cpu, mem} ->
        {slug,
         %{
           id: slug,
           name: name,
           slug: slug,
           category: cat,
           status: "healthy",
           baseline_latency_ms: lat,
           baseline_error_rate: err,
           baseline_cpu: cpu,
           baseline_memory_mb: mem,
           latency_ms: lat,
           error_rate: err,
           cpu_pct: cpu,
           memory_mb: mem,
           pos_x: px,
           pos_y: py,
           metadata: %{},
           active_faults_count: 0
         }}
      end)
      |> Map.new()

    deps = [
      %{
        source: "api-gateway",
        target: "auth-service",
        protocol: "http",
        latency_ms: 8,
        critical: true
      },
      %{
        source: "api-gateway",
        target: "order-service",
        protocol: "http",
        latency_ms: 15,
        critical: true
      },
      %{
        source: "auth-service",
        target: "user-service",
        protocol: "grpc",
        latency_ms: 10,
        critical: true
      },
      %{
        source: "user-service",
        target: "postgres-db",
        protocol: "sql",
        latency_ms: 6,
        critical: true
      },
      %{
        source: "user-service",
        target: "redis-cache",
        protocol: "tcp",
        latency_ms: 2,
        critical: false
      },
      %{
        source: "order-service",
        target: "payment-service",
        protocol: "http",
        latency_ms: 25,
        critical: true
      },
      %{
        source: "order-service",
        target: "inventory-service",
        protocol: "grpc",
        latency_ms: 14,
        critical: true
      },
      %{
        source: "order-service",
        target: "message-queue",
        protocol: "tcp",
        latency_ms: 4,
        critical: false
      },
      %{
        source: "message-queue",
        target: "notification-worker",
        protocol: "tcp",
        latency_ms: 12,
        critical: false
      },
      %{
        source: "payment-service",
        target: "postgres-db",
        protocol: "sql",
        latency_ms: 8,
        critical: true
      },
      %{
        source: "inventory-service",
        target: "postgres-db",
        protocol: "sql",
        latency_ms: 7,
        critical: true
      }
    ]

    {svcs, deps}
  end

  defp persist_fault_record(fault) do
    if Application.get_env(:bug_town, :persist_simulation_records, true) do
      try do
        %Fault{}
        |> Fault.changeset(%{
          fault_type: fault.type,
          severity: fault.severity,
          status: "active",
          parameters: fault.params,
          injected_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()
      rescue
        _ -> :ok
      end
    end
  end

  defp persist_recovery_record(recovery) do
    if Application.get_env(:bug_town, :persist_simulation_records, true) do
      try do
        %RecoveryAction{}
        |> RecoveryAction.changeset(%{
          action_type: recovery.type,
          status: "applied",
          parameters: recovery.params,
          metrics_before: recovery.metrics_before,
          success: recovery.success,
          applied_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()
      rescue
        _ -> :ok
      end
    end
  end

  defp persist_metric_sample(metrics) do
    if Application.get_env(:bug_town, :persist_simulation_records, true) do
      try do
        %MetricSample{}
        |> MetricSample.changeset(%{
          service_slug: "global",
          rps: metrics.total_rps,
          avg_latency_ms: metrics.avg_latency_ms,
          p95_latency_ms: metrics.p95_latency_ms,
          error_rate: metrics.error_rate,
          availability_pct: metrics.health_pct,
          recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()
      rescue
        _ -> :ok
      end
    end
  end
end
