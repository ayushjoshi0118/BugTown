defmodule BugTown.Engine.Scenarios do
  @moduledoc """
  Built-in deterministic chaos scenarios for BugTown experiments.
  """

  @scenarios [
    %{
      id: "memory_leak_exhaustion",
      name: "Memory Leak Causing Service Exhaustion",
      category: "Resource Contention",
      description:
        "Injects an aggressive heap leak into the User Service. Memory grows by 45MB/s, causing GC pause spikes, latency degradation, and eventual OOM crash.",
      target_service: "user-service",
      fault_type: "memory_leak",
      fault_params: %{
        "growth_rate_mb" => 45,
        "max_memory_mb" => 800,
        "duration_ticks" => 50
      },
      recommended_recovery: "restart",
      recovery_params: %{},
      expected_behavior:
        "Memory climbs steadily to 800MB. Status shifts from Healthy to Degraded to Failing. Restart resets heap and restores healthy state."
    },
    %{
      id: "database_cascading_failure",
      name: "Database Outage Causing Cascading Failures",
      category: "Dependency Cascade",
      description:
        "Simulates complete connection failure on the primary PostgreSQL Database. Upstream User, Payment, and Inventory services cascade into failure, eventually degrading API Gateway.",
      target_service: "postgres-db",
      fault_type: "database_failure",
      fault_params: %{
        "mode" => "connection_failure",
        "duration_ticks" => 60
      },
      recommended_recovery: "cache_fallback",
      recovery_params: %{"stale_ttl_seconds" => 300},
      expected_behavior:
        "Postgres goes down. Bugs spawn and propagate upstream to User and Order services. Cache fallback absorbs read load and preserves availability."
    },
    %{
      id: "network_latency_timeouts",
      name: "Network Latency Causing Request Timeouts",
      category: "Network & Transport",
      description:
        "Adds 450ms latency with 50ms jitter across Payment Service dependencies, triggering client timeouts on Order Service checkout calls.",
      target_service: "payment-service",
      fault_type: "network_latency",
      fault_params: %{
        "added_latency_ms" => 450,
        "jitter_ms" => 50,
        "duration_ticks" => 45
      },
      recommended_recovery: "adjust_timeout",
      recovery_params: %{"timeout_ms" => 800},
      expected_behavior:
        "Checkout p95 latency spikes to ~550ms. Timeout adjustments or circuit breakers prevent client request drops."
    },
    %{
      id: "packet_loss_amplification",
      name: "Packet Loss Causing Retry Amplification",
      category: "Network & Transport",
      description:
        "Introduces 35% packet drop probability on Order Service ingress, causing dropped requests and uncoordinated retry storms.",
      target_service: "order-service",
      fault_type: "packet_loss",
      fault_params: %{
        "loss_probability" => 0.35,
        "duration_ticks" => 50
      },
      recommended_recovery: "bounded_retries",
      recovery_params: %{"max_retries" => 3, "backoff_ms" => 50},
      expected_behavior:
        "Error rate increases to ~30%. Enabling bounded retries with exponential backoff recovers effective delivery."
    },
    %{
      id: "race_condition_conflicts",
      name: "Race Condition Causing Inconsistent Logical Updates",
      category: "Concurrency",
      description:
        "Simulates high concurrency without distributed locks on Inventory Service stock reservations, leading to optimistic lock failures and stock inconsistencies.",
      target_service: "inventory-service",
      fault_type: "race_condition",
      fault_params: %{
        "concurrency_intensity" => 0.85,
        "conflict_probability" => 0.60,
        "duration_ticks" => 45
      },
      recommended_recovery: "race_mitigation",
      recovery_params: %{"mechanism" => "distributed_mutex"},
      expected_behavior:
        "High error rate from concurrent conflicting updates. Applying mutex synchronization eliminates collisions."
    },
    %{
      id: "circuit_breaker_isolation",
      name: "Circuit Breaker Preventing Cascading Failures",
      category: "Resilience Pattern",
      description:
        "Simulates a slow query and connection pool starvation on Postgres. Injects failure, then activates circuit breaker on Order Service to isolate the cascade.",
      target_service: "postgres-db",
      fault_type: "database_failure",
      fault_params: %{
        "mode" => "pool_exhaustion",
        "duration_ticks" => 60
      },
      recommended_recovery: "circuit_breaker",
      recovery_params: %{"error_threshold_pct" => 20, "trip_timeout_ms" => 5000},
      expected_behavior:
        "Without breaker, errors cascade to API Gateway. With circuit breaker enabled, callers fail-fast without queuing."
    },
    %{
      id: "restart_policy_crash",
      name: "Restart Policy Recovering a Crashed Service",
      category: "Lifecycle & OTP",
      description:
        "Simulates hard process kill (SIGKILL) on Payment Service. Demonstrates supervisor restart detection and recovery sequence.",
      target_service: "payment-service",
      fault_type: "service_crash",
      fault_params: %{
        "crash_mode" => "sigkill",
        "auto_restart" => false,
        "duration_ticks" => 60
      },
      recommended_recovery: "restart",
      recovery_params: %{},
      expected_behavior:
        "Service immediately drops to Offline. Dependent checkout calls return 502/504. Manual or supervisor restart transitions to recovering and healthy."
    },
    %{
      id: "cache_fallback_resilience",
      name: "Cache Fallback Preserving Partial Availability",
      category: "Resilience Pattern",
      description:
        "User Service experiences database disconnection. Demonstrates how Redis cache fallback maintains read availability despite downstream database outage.",
      target_service: "user-service",
      fault_type: "database_failure",
      fault_params: %{
        "mode" => "connection_failure",
        "duration_ticks" => 60
      },
      recommended_recovery: "cache_fallback",
      recovery_params: %{"serve_stale" => true},
      expected_behavior:
        "With cache fallback enabled, user authentication and profile reads hit cache, keeping error rate under 5%."
    }
  ]

  @doc """
  Lists all available built-in scenarios.
  """
  def all, do: @scenarios

  @doc """
  Finds a scenario by ID.
  """
  def get(id) do
    Enum.find(@scenarios, fn s -> s.id == id end)
  end
end
