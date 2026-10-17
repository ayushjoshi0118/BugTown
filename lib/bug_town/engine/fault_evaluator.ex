defmodule BugTown.Engine.FaultEvaluator do
  @moduledoc """
  Evaluates active faults on each simulation tick and computes target service state modifications.
  """

  @doc """
  Applies active faults to the current map of services and dependencies.
  Returns updated {services, active_faults, generated_logs}.
  """
  def evaluate_faults(services, dependencies, active_faults, active_recoveries, tick_count) do
    # Expire completed faults first
    {active_faults, expired_logs} = expire_faults(active_faults, tick_count)

    # Step each active fault and apply effects to services
    {updated_services, updated_faults, fault_logs} =
      Enum.reduce(active_faults, {services, %{}, []}, fn {fault_id, fault},
                                                         {svc_acc, flt_acc, log_acc} ->
        {new_svcs, updated_fault, new_logs} =
          apply_fault(fault, svc_acc, dependencies, active_recoveries, tick_count)

        {new_svcs, Map.put(flt_acc, fault_id, updated_fault), log_acc ++ new_logs}
      end)

    {updated_services, updated_faults, expired_logs ++ fault_logs}
  end

  defp expire_faults(active_faults, tick_count) do
    Enum.reduce(active_faults, {%{}, []}, fn {id, fault}, {acc_faults, acc_logs} ->
      duration = Map.get(fault, :duration_ticks, 60)
      injected_at = Map.get(fault, :injected_at_tick, 0)

      if duration > 0 and tick_count - injected_at >= duration do
        log = %{
          timestamp: DateTime.utc_now(),
          severity: "info",
          service_name: fault.target || "system",
          event_type: "fault_expired",
          correlation_id: "flt-#{id}",
          message: "Fault #{fault.type} naturally expired after #{duration} ticks."
        }

        {acc_faults, [log | acc_logs]}
      else
        {Map.put(acc_faults, id, fault), acc_logs}
      end
    end)
  end

  defp apply_fault(%{type: "memory_leak"} = fault, services, _deps, recoveries, tick_count) do
    target_slug = fault.target
    service = Map.get(services, target_slug)

    if service do
      # Check if memory reclamation or restart was applied
      has_reclamation = has_recovery?(recoveries, target_slug, ["restart", "memory_reclamation"])

      if has_reclamation do
        # Recovered
        recovered_svc = %{
          service
          | memory_mb: service.baseline_memory_mb,
            cpu_pct: service.baseline_cpu,
            status: "healthy",
            active_faults_count: max(0, service.active_faults_count - 1)
        }

        {Map.put(services, target_slug, recovered_svc), %{fault | status: "mitigated"}, []}
      else
        params = fault.params || %{}
        growth_rate = Map.get(params, "growth_rate_mb", 25)
        max_threshold = Map.get(params, "max_memory_mb", 950)

        current_mem = service.memory_mb + growth_rate
        elapsed = tick_count - fault.injected_at_tick

        {new_status, new_cpu, new_latency, new_err, logs} =
          cond do
            current_mem >= max_threshold ->
              logs =
                if rem(elapsed, 5) == 0 do
                  [
                    %{
                      timestamp: DateTime.utc_now(),
                      severity: "fatal",
                      service_name: service.name,
                      event_type: "out_of_memory",
                      correlation_id: "flt-#{fault.id}",
                      message:
                        "OOM killer invoked on #{service.name}! Memory usage reached #{current_mem}MB / #{max_threshold}MB."
                    }
                  ]
                else
                  []
                end

              {"failing", 98.5, service.baseline_latency_ms * 8, 0.65, logs}

            current_mem >= max_threshold * 0.70 ->
              logs =
                if rem(elapsed, 10) == 0 do
                  [
                    %{
                      timestamp: DateTime.utc_now(),
                      severity: "warn",
                      service_name: service.name,
                      event_type: "gc_pressure",
                      correlation_id: "flt-#{fault.id}",
                      message: "High GC pause times on #{service.name}. Heap at #{current_mem}MB."
                    }
                  ]
                else
                  []
                end

              {"degraded", min(85.0, service.cpu_pct + 12.0), service.baseline_latency_ms * 3,
               0.08, logs}

            true ->
              {service.status, min(65.0, service.cpu_pct + 3.0), service.latency_ms,
               service.error_rate, []}
          end

        updated_svc = %{
          service
          | memory_mb: current_mem,
            cpu_pct: new_cpu,
            latency_ms: new_latency,
            error_rate: new_err,
            status: new_status,
            active_faults_count: max(1, service.active_faults_count)
        }

        {Map.put(services, target_slug, updated_svc), fault, logs}
      end
    else
      {services, fault, []}
    end
  end

  defp apply_fault(%{type: "race_condition"} = fault, services, _deps, recoveries, tick_count) do
    target_slug = fault.target
    service = Map.get(services, target_slug)

    if service do
      has_mitigation =
        has_recovery?(recoveries, target_slug, ["race_mitigation", "locking", "serialization"])

      if has_mitigation do
        # Mutex locking or serialized isolation mitigates race
        updated_svc = %{
          service
          | error_rate: service.baseline_error_rate,
            # slight locking overhead
            latency_ms: service.baseline_latency_ms + 8,
            status: "healthy"
        }

        {Map.put(services, target_slug, updated_svc), %{fault | status: "mitigated"}, []}
      else
        params = fault.params || %{}
        intensity = Map.get(params, "concurrency_intensity", 0.7)
        conflict_prob = Map.get(params, "conflict_probability", 0.45)

        induced_error = Float.round(intensity * conflict_prob * 0.6, 3)

        logs =
          if rem(tick_count - fault.injected_at_tick, 4) == 0 do
            [
              %{
                timestamp: DateTime.utc_now(),
                severity: "error",
                service_name: service.name,
                event_type: "race_conflict",
                correlation_id: "flt-#{fault.id}",
                message:
                  "Detected concurrent write collision on #{service.name}! Optimistic lock failure on state transition."
              }
            ]
          else
            []
          end

        updated_svc = %{
          service
          | error_rate: max(service.error_rate, induced_error),
            status: if(induced_error > 0.15, do: "degraded", else: "healthy"),
            active_faults_count: max(1, service.active_faults_count)
        }

        {Map.put(services, target_slug, updated_svc), fault, logs}
      end
    else
      {services, fault, []}
    end
  end

  defp apply_fault(%{type: "service_crash"} = fault, services, _deps, recoveries, tick_count) do
    target_slug = fault.target
    service = Map.get(services, target_slug)

    if service do
      has_restart = has_recovery?(recoveries, target_slug, ["restart", "restart_dependents"])

      if has_restart do
        recovered_svc = %{
          service
          | status: "recovering",
            cpu_pct: service.baseline_cpu,
            memory_mb: service.baseline_memory_mb,
            error_rate: 0.05,
            active_faults_count: max(0, service.active_faults_count - 1)
        }

        {Map.put(services, target_slug, recovered_svc), %{fault | status: "mitigated"}, []}
      else
        elapsed = tick_count - fault.injected_at_tick
        params = fault.params || %{}
        auto_restart = Map.get(params, "auto_restart", false)
        restart_after = Map.get(params, "restart_after_ticks", 15)

        if auto_restart and elapsed >= restart_after do
          recovering_svc = %{
            service
            | status: "recovering",
              cpu_pct: service.baseline_cpu,
              error_rate: 0.05,
              active_faults_count: max(0, service.active_faults_count - 1)
          }

          log = %{
            timestamp: DateTime.utc_now(),
            severity: "info",
            service_name: service.name,
            event_type: "supervisor_restart",
            correlation_id: "flt-#{fault.id}",
            message: "Supervisor automatically restarted #{service.name} after backoff."
          }

          {Map.put(services, target_slug, recovering_svc), %{fault | status: "expired"}, [log]}
        else
          crashed_svc = %{
            service
            | status: "offline",
              cpu_pct: 0.0,
              error_rate: 1.0,
              active_faults_count: max(1, service.active_faults_count)
          }

          logs =
            if elapsed == 0 do
              [
                %{
                  timestamp: DateTime.utc_now(),
                  severity: "fatal",
                  service_name: service.name,
                  event_type: "service_died",
                  correlation_id: "flt-#{fault.id}",
                  message: "Service #{service.name} crashed abruptly (SIGKILL/panic)."
                }
              ]
            else
              []
            end

          {Map.put(services, target_slug, crashed_svc), fault, logs}
        end
      end
    else
      {services, fault, []}
    end
  end

  defp apply_fault(%{type: "network_latency"} = fault, services, _deps, recoveries, tick_count) do
    target_slug = fault.target
    service = Map.get(services, target_slug)

    if service do
      has_timeout_adj =
        has_recovery?(recoveries, target_slug, ["adjust_timeout", "circuit_breaker"])

      params = fault.params || %{}
      added_lat = Map.get(params, "added_latency_ms", 350)
      jitter = Map.get(params, "jitter_ms", 40)
      noise = :rand.uniform(max(1, jitter * 2)) - jitter
      total_added = max(10, added_lat + noise)

      new_latency = service.baseline_latency_ms + total_added
      new_error = if has_timeout_adj, do: 0.04, else: min(0.40, total_added / 1200.0)

      logs =
        if rem(tick_count - fault.injected_at_tick, 8) == 0 do
          [
            %{
              timestamp: DateTime.utc_now(),
              severity: "warn",
              service_name: service.name,
              event_type: "network_latency_spike",
              correlation_id: "flt-#{fault.id}",
              message: "Network link latency spiked by +#{total_added}ms on #{service.name}."
            }
          ]
        else
          []
        end

      updated_svc = %{
        service
        | latency_ms: new_latency,
          error_rate: max(service.error_rate, new_error),
          status: if(new_latency > 300, do: "degraded", else: "healthy"),
          active_faults_count: max(1, service.active_faults_count)
      }

      {Map.put(services, target_slug, updated_svc), fault, logs}
    else
      {services, fault, []}
    end
  end

  defp apply_fault(%{type: "packet_loss"} = fault, services, _deps, recoveries, tick_count) do
    target_slug = fault.target
    service = Map.get(services, target_slug)

    if service do
      has_retries = has_recovery?(recoveries, target_slug, ["bounded_retries", "rate_limiting"])

      params = fault.params || %{}
      loss_prob = Map.get(params, "loss_probability", 0.35)

      # If bounded retries active, effective error is lowered by retry backoff
      effective_err = if has_retries, do: loss_prob * 0.15, else: loss_prob * 0.9
      added_lat = if has_retries, do: 65, else: 15

      logs =
        if rem(tick_count - fault.injected_at_tick, 6) == 0 do
          [
            %{
              timestamp: DateTime.utc_now(),
              severity: "error",
              service_name: service.name,
              event_type: "packet_drop",
              correlation_id: "flt-#{fault.id}",
              message:
                "Packet loss observed: #{round(loss_prob * 100)}% drop rate on #{service.name} ingress/egress."
            }
          ]
        else
          []
        end

      updated_svc = %{
        service
        | error_rate: max(service.error_rate, effective_err),
          latency_ms: service.latency_ms + added_lat,
          status: if(effective_err > 0.10, do: "degraded", else: "healthy"),
          active_faults_count: max(1, service.active_faults_count)
      }

      {Map.put(services, target_slug, updated_svc), fault, logs}
    else
      {services, fault, []}
    end
  end

  defp apply_fault(%{type: "database_failure"} = fault, services, _deps, recoveries, tick_count) do
    target_slug = fault.target || "postgres-db"
    service = Map.get(services, target_slug)

    if service do
      has_pool_adj = has_recovery?(recoveries, target_slug, ["pool_adjustment", "restart"])

      has_cache_fallback =
        has_recovery?(recoveries, "user-service", ["cache_fallback"]) or
          has_recovery?(recoveries, "order-service", ["cache_fallback"])

      params = fault.params || %{}
      # "connection_failure", "slow_queries", "pool_exhaustion"
      mode = Map.get(params, "mode", "slow_queries")

      {new_status, new_lat, new_err, logs} =
        case mode do
          "connection_failure" ->
            l =
              if rem(tick_count - fault.injected_at_tick, 5) == 0 do
                [
                  %{
                    timestamp: DateTime.utc_now(),
                    severity: "fatal",
                    service_name: service.name,
                    event_type: "db_connection_refused",
                    correlation_id: "flt-#{fault.id}",
                    message:
                      "FATAL: Connection to PostgreSQL database failed! TCP connection refused on port 5432."
                  }
                ]
              else
                []
              end

            {"failing", 1200, 0.95, l}

          "pool_exhaustion" ->
            if has_pool_adj do
              {"healthy", service.baseline_latency_ms + 10, 0.01, []}
            else
              l =
                if rem(tick_count - fault.injected_at_tick, 6) == 0 do
                  [
                    %{
                      timestamp: DateTime.utc_now(),
                      severity: "error",
                      service_name: service.name,
                      event_type: "db_pool_exhausted",
                      correlation_id: "flt-#{fault.id}",
                      message:
                        "Connection pool exhausted (100/100 active connections). 42 client queries waiting in queue."
                    }
                  ]
                else
                  []
                end

              {"failing", 850, 0.55, l}
            end

          _slow_queries ->
            l =
              if rem(tick_count - fault.injected_at_tick, 8) == 0 do
                [
                  %{
                    timestamp: DateTime.utc_now(),
                    severity: "warn",
                    service_name: service.name,
                    event_type: "slow_query",
                    correlation_id: "flt-#{fault.id}",
                    message:
                      "High execution time on table scan: query duration exceeded 500ms threshold."
                  }
                ]
              else
                []
              end

            {"degraded", 450, 0.18, l}
        end

      effective_err = if has_cache_fallback, do: new_err * 0.4, else: new_err

      updated_svc = %{
        service
        | status: new_status,
          latency_ms: new_lat,
          error_rate: effective_err,
          cpu_pct: min(92.0, service.cpu_pct + 35.0),
          active_faults_count: max(1, service.active_faults_count)
      }

      {Map.put(services, target_slug, updated_svc), fault, logs}
    else
      {services, fault, []}
    end
  end

  defp apply_fault(_other, services, _deps, _recoveries, _tick_count) do
    {services, %{}, []}
  end

  defp has_recovery?(recoveries, target_slug, allowed_types) do
    Enum.any?(recoveries, fn {_id, rec} ->
      (rec.target == target_slug or rec.target == "global") and
        rec.type in allowed_types and
        rec.status == "applied"
    end)
  end
end
