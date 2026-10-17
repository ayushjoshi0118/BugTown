defmodule BugTown.Engine.TrafficSimulator do
  @moduledoc """
  Simulates live request traffic across dependencies, produces animated SVG packets,
  evaluates end-to-end latencies and error rates, and generates distributed traces.
  """

  @doc """
  Advances traffic packets, computes global metrics, and generates sample traces.
  Returns {updated_packets, global_metrics, new_traces}.
  """
  def step_traffic(services, dependencies, current_packets, tick_count) do
    # 1. Advance or refresh animated packets
    updated_packets = update_packets(services, dependencies, current_packets, tick_count)

    # 2. Compute aggregate metrics from live services
    global_metrics = compute_global_metrics(services)

    # 3. Generate 1-2 realistic distributed traces each tick reflecting current conditions
    new_traces = generate_traces(services, dependencies, tick_count)

    {updated_packets, global_metrics, new_traces}
  end

  defp update_packets(services, dependencies, current_packets, tick_count) do
    # Filter out packets that reached progress >= 1.0
    active =
      current_packets
      |> Enum.map(fn p -> %{p | progress: Float.round(p.progress + 0.25, 2)} end)
      |> Enum.reject(fn p -> p.progress >= 1.0 end)

    # If count is below target (e.g. 10 packets), spawn new packets along active dependencies
    needed = max(0, 10 - length(active))

    new_packets =
      dependencies
      |> Enum.shuffle()
      |> Enum.take(needed)
      |> Enum.with_index()
      |> Enum.map(fn {dep, idx} ->
        src_svc = Map.get(services, dep.source)
        tgt_svc = Map.get(services, dep.target)

        status =
          cond do
            tgt_svc == nil or src_svc == nil -> "ok"
            tgt_svc.status in ["offline", "failing"] -> "error"
            tgt_svc.error_rate > 0.15 or tgt_svc.status == "degraded" -> "degraded"
            src_svc.error_rate > 0.15 -> "degraded"
            true -> "ok"
          end

        latency = if tgt_svc, do: tgt_svc.latency_ms, else: 15

        %{
          id: "pkt-#{tick_count}-#{idx}-#{:rand.uniform(1000)}",
          from: dep.source,
          to: dep.target,
          # "ok", "degraded", "error"
          status: status,
          progress: 0.0,
          latency: latency
        }
      end)

    active ++ new_packets
  end

  defp compute_global_metrics(services) do
    list = Map.values(services)
    total_count = max(1, length(list))

    healthy_count = Enum.count(list, &(&1.status == "healthy"))
    degraded_count = Enum.count(list, &(&1.status == "degraded"))
    failing_count = Enum.count(list, &(&1.status in ["failing", "offline"]))

    # Weight health: healthy = 100%, degraded = 50%, failing = 0%
    health_score =
      (healthy_count * 100.0 + degraded_count * 50.0 + failing_count * 0.0) /
        (total_count * 100.0) * 100.0

    avg_lat =
      list
      |> Enum.map(& &1.latency_ms)
      |> Enum.sum()
      |> Kernel./(total_count)
      |> Float.round(1)

    # Rough p95 estimate
    sorted_lats = Enum.sort(Enum.map(list, & &1.latency_ms))
    p95_idx = max(0, round(length(sorted_lats) * 0.95) - 1)
    p95_lat = Enum.at(sorted_lats, p95_idx, avg_lat) |> Kernel.*(1.35) |> Float.round(1)

    avg_err =
      list
      |> Enum.map(& &1.error_rate)
      |> Enum.sum()
      |> Kernel./(total_count)
      |> Float.round(4)

    # Base TPS is around 120-150, drops if gateway or core services fail
    gw = Map.get(services, "api-gateway")

    gw_mult =
      case if gw, do: gw.status, else: "healthy" do
        "healthy" -> 1.0
        "degraded" -> 0.70
        "failing" -> 0.25
        "offline" -> 0.0
        _ -> 1.0
      end

    base_rps = (115.0 + :rand.uniform(25)) * gw_mult

    %{
      health_pct: Float.round(health_score, 1),
      total_rps: Float.round(base_rps, 1),
      avg_latency_ms: avg_lat,
      p95_latency_ms: p95_lat,
      error_rate: avg_err,
      active_incidents_count: 0,
      healthy_services: healthy_count,
      degraded_services: degraded_count,
      failing_services: failing_count
    }
  end

  defp generate_traces(services, _dependencies, tick_count) do
    # Generate 1 realistic distributed trace per tick
    trace_id = "trc-" <> Integer.to_string(System.unique_integer([:positive]), 16)
    now = DateTime.utc_now()

    # Alternate paths: Order flow vs Auth/User profile flow
    path_type = if rem(tick_count, 2) == 0, do: :order, else: :auth

    {spans, total_duration, overall_status} =
      case path_type do
        :order -> build_order_trace(services, trace_id, now)
        :auth -> build_auth_trace(services, trace_id, now)
      end

    [
      %{
        trace_id: trace_id,
        root_service: "API Gateway",
        path_name:
          if(path_type == :order,
            do: "POST /api/v1/orders/checkout",
            else: "GET /api/v1/users/profile"
          ),
        duration_ms: Float.round(total_duration, 1),
        status: overall_status,
        timestamp: now,
        spans: spans
      }
    ]
  end

  defp build_order_trace(services, _trace_id, _now) do
    gw = Map.get(services, "api-gateway", default_svc("API Gateway"))
    ord = Map.get(services, "order-service", default_svc("Order Service"))
    pay = Map.get(services, "payment-service", default_svc("Payment Service"))
    inv = Map.get(services, "inventory-service", default_svc("Inventory Service"))
    db = Map.get(services, "postgres-db", default_svc("PostgreSQL Database"))
    mq = Map.get(services, "message-queue", default_svc("Message Queue"))

    span_root_id = "sp-gw-#{:rand.uniform(9999)}"
    span_ord_id = "sp-ord-#{:rand.uniform(9999)}"
    span_pay_id = "sp-pay-#{:rand.uniform(9999)}"
    span_inv_id = "sp-inv-#{:rand.uniform(9999)}"
    span_db_id = "sp-db-#{:rand.uniform(9999)}"
    span_mq_id = "sp-mq-#{:rand.uniform(9999)}"

    # Determine status & error for each
    db_status = status_for(db)
    pay_status = if db_status == "error", do: "error", else: status_for(pay)
    inv_status = if db_status == "error", do: "error", else: status_for(inv)

    ord_status =
      if pay_status == "error" or inv_status == "error", do: "error", else: status_for(ord)

    gw_status = if ord_status == "error", do: "error", else: status_for(gw)

    db_dur = Float.round(db.latency_ms * 1.0 + :rand.uniform(5), 1)
    pay_dur = Float.round(pay.latency_ms + db_dur * 0.4, 1)
    inv_dur = Float.round(inv.latency_ms + db_dur * 0.3, 1)
    mq_dur = Float.round(mq.latency_ms * 1.0, 1)
    ord_dur = Float.round(ord.latency_ms + max(pay_dur, inv_dur) + mq_dur, 1)
    gw_dur = Float.round(gw.latency_ms + ord_dur, 1)

    spans = [
      %{
        span_id: span_root_id,
        parent_span_id: nil,
        service_name: "API Gateway",
        operation: "POST /api/v1/orders/checkout",
        start_offset_ms: 0.0,
        duration_ms: gw_dur,
        status: gw_status,
        error_details: if(gw_status == "error", do: "Downstream service error (502 Bad Gateway)")
      },
      %{
        span_id: span_ord_id,
        parent_span_id: span_root_id,
        service_name: "Order Service",
        operation: "OrderOrchestrator.create_order",
        start_offset_ms: 6.0,
        duration_ms: ord_dur,
        status: ord_status,
        error_details:
          if(ord_status == "error", do: "Failed to settle payment / reserve inventory")
      },
      %{
        span_id: span_pay_id,
        parent_span_id: span_ord_id,
        service_name: "Payment Service",
        operation: "PaymentGateway.authorize_charge",
        start_offset_ms: 18.0,
        duration_ms: pay_dur,
        status: pay_status,
        error_details:
          if(pay_status == "error", do: "DB query timed out while saving authorization token")
      },
      %{
        span_id: span_inv_id,
        parent_span_id: span_ord_id,
        service_name: "Inventory Service",
        operation: "Warehouse.reserve_stock",
        start_offset_ms: 22.0,
        duration_ms: inv_dur,
        status: inv_status,
        error_details:
          if(inv_status == "error", do: "Unable to acquire inventory locks on Postgres")
      },
      %{
        span_id: span_db_id,
        parent_span_id: span_pay_id,
        service_name: "PostgreSQL Database",
        operation: "SELECT stock, balance FROM ledgers WHERE ... FOR UPDATE",
        start_offset_ms: 38.0,
        duration_ms: db_dur,
        status: db_status,
        error_details:
          if(db_status == "error", do: "FATAL: connection pool exhausted / lock timeout")
      },
      %{
        span_id: span_mq_id,
        parent_span_id: span_ord_id,
        service_name: "Message Queue",
        operation: "publish(order.events)",
        start_offset_ms: ord_dur - mq_dur,
        duration_ms: mq_dur,
        status: status_for(mq),
        error_details: nil
      }
    ]

    overall_status =
      if gw_status == "error", do: "error", else: if(gw_dur > 150, do: "degraded", else: "ok")

    {spans, gw_dur, overall_status}
  end

  defp build_auth_trace(services, _trace_id, _now) do
    gw = Map.get(services, "api-gateway", default_svc("API Gateway"))
    auth = Map.get(services, "auth-service", default_svc("Authentication Service"))
    user = Map.get(services, "user-service", default_svc("User Service"))
    redis = Map.get(services, "redis-cache", default_svc("Redis Cache"))
    db = Map.get(services, "postgres-db", default_svc("PostgreSQL Database"))

    span_root_id = "sp-gw-#{:rand.uniform(9999)}"
    span_auth_id = "sp-auth-#{:rand.uniform(9999)}"
    span_usr_id = "sp-usr-#{:rand.uniform(9999)}"
    span_red_id = "sp-red-#{:rand.uniform(9999)}"
    span_db_id = "sp-db-#{:rand.uniform(9999)}"

    db_status = status_for(db)
    user_status = if db_status == "error", do: "error", else: status_for(user)
    auth_status = if user_status == "error", do: "error", else: status_for(auth)
    gw_status = if auth_status == "error", do: "error", else: status_for(gw)

    red_dur = Float.round(redis.latency_ms * 1.0, 1)
    db_dur = Float.round(db.latency_ms * 1.0, 1)
    user_dur = Float.round(user.latency_ms + red_dur + db_dur * 0.5, 1)
    auth_dur = Float.round(auth.latency_ms + user_dur, 1)
    gw_dur = Float.round(gw.latency_ms + auth_dur, 1)

    spans = [
      %{
        span_id: span_root_id,
        parent_span_id: nil,
        service_name: "API Gateway",
        operation: "GET /api/v1/users/profile",
        start_offset_ms: 0.0,
        duration_ms: gw_dur,
        status: gw_status,
        error_details:
          if(gw_status == "error", do: "502 Bad Gateway - Authentication upstream failed")
      },
      %{
        span_id: span_auth_id,
        parent_span_id: span_root_id,
        service_name: "Authentication Service",
        operation: "TokenValidator.verify_jwt",
        start_offset_ms: 4.0,
        duration_ms: auth_dur,
        status: auth_status,
        error_details: if(auth_status == "error", do: "User lookup failed")
      },
      %{
        span_id: span_usr_id,
        parent_span_id: span_auth_id,
        service_name: "User Service",
        operation: "UserProfile.get_by_id",
        start_offset_ms: 12.0,
        duration_ms: user_dur,
        status: user_status,
        error_details: if(user_status == "error", do: "Postgres read timeout on users table")
      },
      %{
        span_id: span_red_id,
        parent_span_id: span_usr_id,
        service_name: "Redis Cache",
        operation: "GET session:user:49182",
        start_offset_ms: 16.0,
        duration_ms: red_dur,
        status: status_for(redis),
        error_details: nil
      },
      %{
        span_id: span_db_id,
        parent_span_id: span_usr_id,
        service_name: "PostgreSQL Database",
        operation: "SELECT * FROM users WHERE id = $1 LIMIT 1",
        start_offset_ms: 22.0,
        duration_ms: db_dur,
        status: db_status,
        error_details: if(db_status == "error", do: "Database connection failed")
      }
    ]

    overall_status =
      if gw_status == "error", do: "error", else: if(gw_dur > 100, do: "degraded", else: "ok")

    {spans, gw_dur, overall_status}
  end

  defp status_for(%{status: "offline"}), do: "error"
  defp status_for(%{status: "failing"}), do: "error"
  defp status_for(%{error_rate: err}) when err > 0.20, do: "error"
  defp status_for(%{status: "degraded"}), do: "degraded"
  defp status_for(%{error_rate: err}) when err > 0.05, do: "degraded"
  defp status_for(_), do: "ok"

  defp default_svc(name) do
    %{name: name, status: "healthy", latency_ms: 20, error_rate: 0.001}
  end
end
