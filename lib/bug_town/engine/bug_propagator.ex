defmodule BugTown.Engine.BugPropagator do
  @moduledoc """
  Manages living bug entities: spawning them from faults, propagating them along dependency edges,
  updating lifecycle states, and transitioning them to contained/resolved upon recovery.
  """

  @doc """
  Updates all active bugs and spawns new bugs for unrepresented active faults.
  Returns {updated_bugs, updated_services, generated_logs}.
  """
  def step_bugs(bugs, services, dependencies, active_faults, active_recoveries, tick_count) do
    # 1. Spawn bugs for any newly injected active faults that don't have a bug yet
    bugs = ensure_bugs_for_faults(bugs, active_faults, tick_count)

    # 2. Step each bug: evaluate propagation, containment, and resolution
    {updated_bugs, updated_services, logs} =
      Enum.reduce(bugs, {%{}, services, []}, fn {bug_id, bug}, {b_acc, s_acc, l_acc} ->
        {new_bug, new_services, new_logs} =
          step_single_bug(bug, s_acc, dependencies, active_faults, active_recoveries, tick_count)

        # Retain bugs, or purge resolved bugs after 15 ticks of being resolved
        if keep_bug?(new_bug, tick_count) do
          {Map.put(b_acc, bug_id, new_bug), new_services, l_acc ++ new_logs}
        else
          {b_acc, new_services, l_acc}
        end
      end)

    {updated_bugs, updated_services, logs}
  end

  defp keep_bug?(bug, tick_count) do
    case bug.status do
      "resolved" ->
        # keep for 12 ticks after resolution so UI can show resolution animation
        resolved_tick = Map.get(bug, :resolved_at_tick, tick_count)
        tick_count - resolved_tick < 12

      _other ->
        true
    end
  end

  defp ensure_bugs_for_faults(bugs, active_faults, tick_count) do
    # Group existing bugs by originating fault id
    existing_fault_ids =
      bugs
      |> Enum.map(fn {_id, b} -> b.originating_fault_id end)
      |> MapSet.new()

    Enum.reduce(active_faults, bugs, fn {fault_id, fault}, acc ->
      if fault.status == "active" and not MapSet.member?(existing_fault_ids, fault_id) do
        bug = create_bug_for_fault(fault, tick_count)
        Map.put(acc, bug.id, bug)
      else
        acc
      end
    end)
  end

  defp create_bug_for_fault(fault, tick_count) do
    code_num = :erlang.phash2({fault.id, tick_count}, 9000) + 1000
    bug_code = "BUG-#{code_num}"
    bug_type = map_fault_type_to_bug_type(fault.type)
    target_svc = fault.target || "api-gateway"

    %{
      id: "bug-#{fault.id}-#{tick_count}",
      code: bug_code,
      type: bug_type,
      severity: fault.severity || "high",
      current_service: target_svc,
      originating_fault_id: fault.id,
      originating_service: target_svc,
      # spawned, propagating, active, contained, resolved
      status: "spawned",
      impact_score: initial_impact(fault.severity),
      history: [
        %{
          service: target_svc,
          tick: tick_count,
          timestamp: DateTime.utc_now(),
          event: "Spawned at #{target_svc} from #{fault.type} fault"
        }
      ],
      hops: 0,
      spawned_at_tick: tick_count,
      spawned_at: DateTime.utc_now(),
      resolved_at_tick: nil,
      resolved_at: nil,
      suggested_remedy: suggested_remedy(fault.type, target_svc)
    }
  end

  defp map_fault_type_to_bug_type("memory_leak"), do: "memory_hog"
  defp map_fault_type_to_bug_type("race_condition"), do: "race_demon"
  defp map_fault_type_to_bug_type("service_crash"), do: "crash_worm"
  defp map_fault_type_to_bug_type("network_latency"), do: "latency_parasite"
  defp map_fault_type_to_bug_type("packet_loss"), do: "packet_phantom"
  defp map_fault_type_to_bug_type("database_failure"), do: "db_gremlin"
  defp map_fault_type_to_bug_type(_), do: "chaos_gnome"

  defp initial_impact("critical"), do: 85
  defp initial_impact("high"), do: 65
  defp initial_impact("medium"), do: 40
  defp initial_impact(_), do: 25

  defp suggested_remedy("memory_leak", svc), do: "Restart #{svc} or trigger GC reclamation."

  defp suggested_remedy("race_condition", _),
    do: "Apply concurrency locking or serializable transactions."

  defp suggested_remedy("service_crash", svc),
    do: "Apply supervisor restart policy to restore #{svc}."

  defp suggested_remedy("network_latency", _),
    do: "Enable circuit breaker or tune client request timeouts."

  defp suggested_remedy("packet_loss", _), do: "Enable bounded retries with exponential backoff."

  defp suggested_remedy("database_failure", _),
    do: "Adjust DB connection pool or enable cache fallback."

  defp suggested_remedy(_, svc), do: "Inspect telemetry and restart #{svc}."

  defp step_single_bug(bug, services, dependencies, active_faults, active_recoveries, tick_count) do
    fault = Map.get(active_faults, bug.originating_fault_id)

    # 1. Check if fault was removed or mitigated by recovery
    is_mitigated =
      fault == nil or
        fault.status in ["mitigated", "expired", "removed"] or
        has_effective_recovery?(bug, active_recoveries)

    cond do
      is_mitigated and bug.status != "resolved" ->
        # Transition to contained then resolved
        new_status = if bug.status == "contained", do: "resolved", else: "contained"

        resolved_tick = if new_status == "resolved", do: tick_count, else: bug.resolved_at_tick
        resolved_time = if new_status == "resolved", do: DateTime.utc_now(), else: bug.resolved_at

        history_entry = %{
          service: bug.current_service,
          tick: tick_count,
          timestamp: DateTime.utc_now(),
          event: "Bug #{bug.code} marked as #{new_status} via recovery strategy"
        }

        log = %{
          timestamp: DateTime.utc_now(),
          severity: "info",
          service_name: bug.current_service,
          event_type: "bug_#{new_status}",
          correlation_id: bug.code,
          message: "Living bug #{bug.code} (#{bug.type}) has been #{new_status}."
        }

        updated_bug = %{
          bug
          | status: new_status,
            impact_score: max(0, bug.impact_score - 30),
            history: [history_entry | bug.history],
            resolved_at_tick: resolved_tick,
            resolved_at: resolved_time
        }

        {updated_bug, services, [log]}

      bug.status == "resolved" ->
        # Already resolved
        {bug, services, []}

      true ->
        # Active or propagating: evaluate propagation along caller dependencies
        # In distributed systems, bugs propagate UPSTREAM to callers when downstream fails
        # e.g., if DB fails, User Service and Order Service degrade, then API Gateway degrades
        current_svc = Map.get(services, bug.current_service)
        elapsed = tick_count - bug.spawned_at_tick

        # Check if bug should propagate to an upstream caller (every 5-7 ticks if hops < 2)
        should_propagate =
          elapsed > 3 and
            rem(elapsed, 6) == 0 and
            bug.hops < 2 and
            current_svc != nil and
            current_svc.status in ["degraded", "failing", "offline"]

        if should_propagate do
          # Find upstream services that depend on current_service
          upstream_slugs = find_upstream_services(bug.current_service, dependencies)

          # Pick an upstream caller that isn't already the originating service
          next_target =
            upstream_slugs
            |> Enum.reject(fn slug -> Enum.any?(bug.history, &(&1.service == slug)) end)
            |> List.first()

          if next_target do
            # Check circuit breaker on next_target
            has_circuit_breaker =
              Enum.any?(active_recoveries, fn {_id, rec} ->
                rec.target == next_target and rec.type == "circuit_breaker" and
                  rec.status == "applied"
              end)

            if has_circuit_breaker do
              # Blocked by circuit breaker!
              log = %{
                timestamp: DateTime.utc_now(),
                severity: "info",
                service_name: next_target,
                event_type: "circuit_breaker_intercept",
                correlation_id: bug.code,
                message:
                  "Circuit breaker on #{next_target} intercepted propagation of #{bug.code}!"
              }

              updated_bug = %{
                bug
                | status: "contained",
                  history: [
                    %{
                      service: next_target,
                      tick: tick_count,
                      timestamp: DateTime.utc_now(),
                      event: "Propagation blocked at #{next_target} by active circuit breaker."
                    }
                    | bug.history
                  ]
              }

              {updated_bug, services, [log]}
            else
              # Cascade propagates to upstream service!
              history_entry = %{
                service: next_target,
                tick: tick_count,
                timestamp: DateTime.utc_now(),
                event:
                  "Cascaded from #{bug.current_service} to #{next_target} via dependency link"
              }

              log = %{
                timestamp: DateTime.utc_now(),
                severity: "warn",
                service_name: next_target,
                event_type: "bug_propagated",
                correlation_id: bug.code,
                message:
                  "Cascading failure: #{bug.code} propagated from #{bug.current_service} to #{next_target}."
              }

              # Degrade the upstream service slightly from the cascade
              target_svc_obj = Map.get(services, next_target)

              updated_target_svc =
                if target_svc_obj do
                  %{
                    target_svc_obj
                    | status:
                        if(target_svc_obj.status == "healthy",
                          do: "degraded",
                          else: target_svc_obj.status
                        ),
                      error_rate: max(target_svc_obj.error_rate, 0.12),
                      latency_ms: target_svc_obj.latency_ms + 45
                  }
                else
                  target_svc_obj
                end

              updated_services =
                if updated_target_svc do
                  Map.put(services, next_target, updated_target_svc)
                else
                  services
                end

              updated_bug = %{
                bug
                | status: "propagating",
                  current_service: next_target,
                  hops: bug.hops + 1,
                  impact_score: min(100, bug.impact_score + 15),
                  history: [history_entry | bug.history]
              }

              {updated_bug, updated_services, [log]}
            end
          else
            # No eligible upstream to propagate to; stay active
            {bug, services, []}
          end
        else
          # Still active
          updated_bug =
            if bug.status == "spawned" and elapsed >= 2 do
              %{bug | status: "active"}
            else
              bug
            end

          {updated_bug, services, []}
        end
    end
  end

  defp find_upstream_services(target_slug, dependencies) do
    # dependencies: [%{source: slug, target: slug}]
    # source is caller, target is callee
    # If target fails, callers (source) feel it!
    dependencies
    |> Enum.filter(fn dep -> dep.target == target_slug end)
    |> Enum.map(fn dep -> dep.source end)
  end

  defp has_effective_recovery?(bug, active_recoveries) do
    Enum.any?(active_recoveries, fn {_id, rec} ->
      rec.status == "applied" and
        (rec.target == bug.current_service or rec.target == bug.originating_service or
           rec.target == "global") and
        matches_recovery_type?(bug.type, rec.type)
    end)
  end

  defp matches_recovery_type?("memory_hog", rec_type),
    do: rec_type in ["restart", "restart_dependents", "memory_reclamation"]

  defp matches_recovery_type?("race_demon", rec_type),
    do: rec_type in ["race_mitigation", "locking", "serialization"]

  defp matches_recovery_type?("crash_worm", rec_type),
    do: rec_type in ["restart", "restart_dependents"]

  defp matches_recovery_type?("latency_parasite", rec_type),
    do: rec_type in ["adjust_timeout", "circuit_breaker", "rate_limiting"]

  defp matches_recovery_type?("packet_phantom", rec_type),
    do: rec_type in ["bounded_retries", "rate_limiting"]

  defp matches_recovery_type?("db_gremlin", rec_type),
    do: rec_type in ["pool_adjustment", "cache_fallback", "restart"]

  defp matches_recovery_type?(_, "remove_fault"), do: true
  defp matches_recovery_type?(_, _), do: false
end
