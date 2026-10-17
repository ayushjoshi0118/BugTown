defmodule BugTown.Engine.IncidentManager do
  @moduledoc """
  Detects SLO breaches and service failures, creates deduplicated incidents,
  tracks timeline progression, and auto-resolves when system conditions stabilize.
  """

  @doc """
  Evaluates services and active faults to create or update incidents.
  Returns {updated_incidents, generated_logs}.
  """
  def evaluate_incidents(incidents, services, active_faults, tick_count) do
    # 1. Check for new incidents or existing active ones
    {incidents, new_logs} =
      Enum.reduce(services, {incidents, []}, fn {slug, svc}, {inc_acc, log_acc} ->
        check_service_for_incident(svc, slug, inc_acc, log_acc, active_faults, tick_count)
      end)

    # 2. Check open incidents to see if their underlying conditions resolved
    {incidents, resolved_logs} =
      Enum.reduce(incidents, {%{}, []}, fn {inc_id, incident}, {acc_incs, acc_logs} ->
        if incident.status in ["open", "investigating", "mitigating"] do
          affected_slugs = incident.affected_services

          all_recovered =
            Enum.all?(affected_slugs, fn s ->
              svc = Map.get(services, s)
              svc != nil and svc.status == "healthy" and svc.error_rate < 0.05
            end)

          if all_recovered do
            timeline_entry = %{
              tick: tick_count,
              timestamp: DateTime.utc_now(),
              event: "Health restored across all affected services. Incident marked resolved."
            }

            resolved_incident = %{
              incident
              | status: "resolved",
                resolved_at_tick: tick_count,
                resolved_at: DateTime.utc_now(),
                timeline_events: [timeline_entry | incident.timeline_events]
            }

            log = %{
              timestamp: DateTime.utc_now(),
              severity: "info",
              service_name: List.first(affected_slugs) || "system",
              event_type: "incident_resolved",
              correlation_id: incident.code,
              message: "Incident #{incident.code} resolved: #{incident.title}"
            }

            {Map.put(acc_incs, inc_id, resolved_incident), [log | acc_logs]}
          else
            # Keep as is
            {Map.put(acc_incs, inc_id, incident), acc_logs}
          end
        else
          # Keep resolved incidents (retain up to 30)
          {Map.put(acc_incs, inc_id, incident), acc_logs}
        end
      end)

    {incidents, new_logs ++ resolved_logs}
  end

  defp check_service_for_incident(svc, slug, incidents, logs, active_faults, tick_count) do
    # Criteria for incident:
    # - status is failing/offline OR
    # - error_rate > 0.15 OR
    # - memory_mb > 750 OR
    # - latency_ms > 350
    has_breach? =
      svc.status in ["failing", "offline"] or
        svc.error_rate > 0.15 or
        svc.memory_mb > 750 or
        svc.latency_ms > 350

    if has_breach? do
      # Check if there is already an open incident covering this service
      existing =
        Enum.find(incidents, fn {_id, inc} ->
          inc.status in ["open", "investigating", "mitigating"] and
            slug in inc.affected_services
        end)

      if existing do
        # Already tracked, no duplicate!
        {incidents, logs}
      else
        # Find related fault if any
        related_fault =
          Enum.find_value(active_faults, fn {_fid, f} ->
            if f.target == slug, do: f, else: nil
          end)

        root_cause =
          cond do
            related_fault != nil ->
              "Fault #{related_fault.type} active on #{slug}"

            svc.status == "offline" ->
              "Service #{svc.name} process crashed / unavailable"

            svc.memory_mb > 750 ->
              "Memory saturation / OOM pressure on #{svc.name}"

            svc.error_rate > 0.15 ->
              "Excessive error rate (#{round(svc.error_rate * 100)}%) on #{svc.name}"

            svc.latency_ms > 350 ->
              "Severe latency degradation (#{round(svc.latency_ms)}ms) on #{svc.name}"

            true ->
              "Degraded dependency health"
          end

        severity =
          cond do
            svc.status in ["failing", "offline"] or svc.error_rate > 0.40 -> "critical"
            svc.status == "degraded" or svc.error_rate > 0.15 -> "high"
            true -> "medium"
          end

        inc_num = :erlang.phash2({slug, tick_count}, 8000) + 1000
        inc_code = "INC-#{inc_num}"
        inc_id = "inc-#{slug}-#{tick_count}"
        title = "#{svc.name}: #{root_cause}"

        new_incident = %{
          id: inc_id,
          code: inc_code,
          title: title,
          severity: severity,
          # open, investigating, mitigating, resolved
          status: "open",
          root_cause: root_cause,
          affected_services: [slug],
          related_fault_id: if(related_fault, do: related_fault.id, else: nil),
          timeline_events: [
            %{
              tick: tick_count,
              timestamp: DateTime.utc_now(),
              event: "Automated alert triggered: #{root_cause} (Severity: #{severity})"
            }
          ],
          notes: "",
          created_at_tick: tick_count,
          created_at: DateTime.utc_now(),
          resolved_at_tick: nil,
          resolved_at: nil
        }

        log = %{
          timestamp: DateTime.utc_now(),
          severity: if(severity == "critical", do: "fatal", else: "error"),
          service_name: svc.name,
          event_type: "incident_created",
          correlation_id: inc_code,
          message: "Triggered incident #{inc_code} [#{severity}]: #{title}"
        }

        {Map.put(incidents, inc_id, new_incident), [log | logs]}
      end
    else
      {incidents, logs}
    end
  end
end
