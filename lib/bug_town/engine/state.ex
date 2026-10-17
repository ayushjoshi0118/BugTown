defmodule BugTown.Engine.State do
  @moduledoc """
  Defines the authoritative in-memory simulation state.
  """

  defstruct [
    # :running, :paused, :stopped
    status: :running,
    tick_count: 0,
    # 0.5, 1.0, 2.0, 5.0
    speed: 1.0,
    sim_time_seconds: 0,
    seed: 42,
    # slug => service_state_map
    services: %{},
    # [%{source: slug, target: slug, latency: ms, critical: bool, protocol: string}]
    dependencies: [],
    # fault_id => %{id, type, target, params, injected_at_tick, duration_ticks}
    active_faults: %{},
    # recovery_id => %{id, type, target, params, applied_at_tick}
    active_recoveries: %{},
    # bug_id => %{id, code, type, severity, current_service, originating_fault_id, status, impact_score, history, hops}
    bugs: %{},
    # active in-flight request visual packets [%{id, from, to, status, progress, latency}]
    traffic_packets: [],
    global_metrics: %{
      health_pct: 100.0,
      total_rps: 120.0,
      avg_latency_ms: 24.5,
      p95_latency_ms: 58.0,
      error_rate: 0.001,
      active_incidents_count: 0,
      healthy_services: 10,
      degraded_services: 0,
      failing_services: 0
    },
    # incident_id => incident_map
    incidents: %{},
    # rolling list of last 60 global metric snapshots
    history_metrics: [],
    # rolling list of last 40 structured logs
    recent_logs: [],
    # rolling list of last 15 distributed waterfall traces
    recent_traces: [],
    # %{name, scenario_type, started_at_tick, baseline_metrics}
    current_experiment: nil
  ]

  @type t :: %__MODULE__{}
end
