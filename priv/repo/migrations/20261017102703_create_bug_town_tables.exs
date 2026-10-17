defmodule BugTown.Repo.Migrations.CreateBugTownTables do
  use Ecto.Migration

  def change do
    # Services
    create table(:services) do
      add :name, :string, null: false
      add :slug, :string, null: false
      # gateway, service, database, cache, queue, worker
      add :category, :string, null: false
      # healthy, degraded, failing, recovering, offline
      add :status, :string, default: "healthy", null: false
      add :baseline_latency_ms, :integer, default: 20, null: false
      add :baseline_error_rate, :float, default: 0.001, null: false
      add :baseline_cpu, :float, default: 15.0, null: false
      add :baseline_memory_mb, :integer, default: 256, null: false
      add :pos_x, :integer, default: 100, null: false
      add :pos_y, :integer, default: 100, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:services, [:slug])

    # Service Dependencies
    create table(:service_dependencies) do
      add :source_service_id, references(:services, on_delete: :delete_all), null: false
      add :target_service_id, references(:services, on_delete: :delete_all), null: false
      # http, grpc, tcp, sql
      add :protocol, :string, default: "http"
      add :latency_ms, :integer, default: 5
      add :critical, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:service_dependencies, [:source_service_id])
    create index(:service_dependencies, [:target_service_id])
    create unique_index(:service_dependencies, [:source_service_id, :target_service_id])

    # Faults
    create table(:faults) do
      # memory_leak, race_condition, service_crash, network_latency, packet_loss, database_failure
      add :fault_type, :string, null: false
      add :target_service_id, references(:services, on_delete: :nilify_all)
      add :target_dependency_id, references(:service_dependencies, on_delete: :nilify_all)
      # active, expired, mitigated, removed
      add :status, :string, default: "active", null: false
      # low, medium, high, critical
      add :severity, :string, default: "high", null: false
      add :parameters, :map, default: %{}, null: false
      add :injected_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:faults, [:target_service_id])
    create index(:faults, [:status])

    # Living Bug Entities
    create table(:bug_entities) do
      # e.g. BUG-4982
      add :entity_code, :string, null: false
      # memory_hog, race_demon, connection_leech, latency_parasite, packet_phantom, crash_worm
      add :bug_type, :string, null: false
      add :severity, :string, default: "high", null: false
      add :current_service_id, references(:services, on_delete: :nilify_all)
      add :originating_fault_id, references(:faults, on_delete: :nilify_all)
      # spawned, propagating, active, contained, resolved
      add :status, :string, default: "spawned", null: false
      add :impact_score, :integer, default: 50
      add :movement_history, {:array, :map}, default: []
      add :spawned_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:bug_entities, [:current_service_id])
    create index(:bug_entities, [:status])
    create unique_index(:bug_entities, [:entity_code])

    # Incidents
    create table(:incidents) do
      # e.g. INC-1024
      add :incident_code, :string, null: false
      add :title, :string, null: false
      # low, medium, high, critical
      add :severity, :string, default: "high", null: false
      # open, investigating, mitigating, resolved
      add :status, :string, default: "open", null: false
      add :root_cause, :string
      add :affected_service_names, {:array, :string}, default: []
      add :related_fault_id, references(:faults, on_delete: :nilify_all)
      add :timeline_events, {:array, :map}, default: []
      add :notes, :text
      add :acknowledged_at, :utc_datetime
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:incidents, [:status])
    create index(:incidents, [:severity])
    create unique_index(:incidents, [:incident_code])

    # Experiments
    create table(:experiments) do
      add :name, :string, null: false
      add :scenario_type, :string, null: false
      add :description, :text
      add :seed, :integer, default: 42
      # running, completed, aborted
      add :status, :string, default: "completed", null: false
      add :fault_config, :map, default: %{}
      add :recovery_config, :map, default: %{}
      # before, during, after metrics
      add :metrics_summary, :map, default: %{}
      add :duration_seconds, :integer, default: 60
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:experiments, [:scenario_type])

    # Recovery Actions
    create table(:recovery_actions) do
      # restart, restart_dependents, circuit_breaker, adjust_timeout, bounded_retries, rate_limiting, cache_fallback, bulkhead, pool_adjustment, race_mitigation, remove_fault
      add :action_type, :string, null: false
      add :target_service_id, references(:services, on_delete: :nilify_all)
      # applied, verified, failed
      add :status, :string, default: "applied", null: false
      add :parameters, :map, default: %{}
      add :metrics_before, :map, default: %{}
      add :metrics_after, :map, default: %{}
      add :time_to_recovery_ms, :integer
      add :success, :boolean, default: false
      add :applied_at, :utc_datetime, null: false
      add :verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:recovery_actions, [:target_service_id])

    # Metric Samples (for time-series snapshots)
    create table(:metric_samples) do
      # "global" or service slug
      add :service_slug, :string, null: false
      add :rps, :float, default: 0.0
      add :avg_latency_ms, :float, default: 0.0
      add :p95_latency_ms, :float, default: 0.0
      add :error_rate, :float, default: 0.0
      add :cpu_pct, :float, default: 0.0
      add :memory_mb, :float, default: 0.0
      add :queue_depth, :integer, default: 0
      add :cache_hit_rate, :float, default: 0.0
      add :db_latency_ms, :float, default: 0.0
      add :availability_pct, :float, default: 100.0
      add :recorded_at, :utc_datetime, null: false
    end

    create index(:metric_samples, [:service_slug, :recorded_at])

    # Structured Logs
    create table(:log_entries) do
      add :timestamp, :utc_datetime, null: false
      # debug, info, warn, error, fatal
      add :severity, :string, null: false
      add :service_name, :string, null: false
      add :event_type, :string, null: false
      add :correlation_id, :string
      add :message, :text, null: false
      add :details, :map, default: %{}
    end

    create index(:log_entries, [:timestamp])
    create index(:log_entries, [:service_name])
    create index(:log_entries, [:severity])

    # Distributed Traces & Spans
    create table(:traces) do
      add :trace_id, :string, null: false
      add :root_service, :string, null: false
      add :duration_ms, :float, null: false
      # ok, degraded, error
      add :status, :string, default: "ok", null: false
      add :timestamp, :utc_datetime, null: false
    end

    create unique_index(:traces, [:trace_id])
    create index(:traces, [:timestamp])

    create table(:spans) do
      add :span_id, :string, null: false
      add :trace_id, :string, null: false
      add :parent_span_id, :string
      add :service_name, :string, null: false
      add :start_time, :utc_datetime, null: false
      add :duration_ms, :float, null: false
      add :status, :string, default: "ok", null: false
      add :error_details, :string
    end

    create index(:spans, [:trace_id])
  end
end
