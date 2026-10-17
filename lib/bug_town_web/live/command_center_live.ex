defmodule BugTownWeb.CommandCenterLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper
  alias BugTown.Engine.Coordinator

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveHelper.setup_sim(:command_center, "Command Center · BugTown")
      |> assign(:selected_service_slug, nil)
      |> assign(:selected_bug_id, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_service", %{"slug" => slug}, socket) do
    current = socket.assigns.selected_service_slug
    new_sel = if current == slug, do: nil, else: slug
    {:noreply, assign(socket, :selected_service_slug, new_sel)}
  end

  @impl true
  def handle_event("select_bug", %{"id" => bug_id}, socket) do
    current = socket.assigns.selected_bug_id
    new_sel = if current == bug_id, do: nil, else: bug_id
    {:noreply, assign(socket, :selected_bug_id, new_sel)}
  end

  @impl true
  def handle_event("close_drawer", _params, socket) do
    {:noreply, socket |> assign(:selected_service_slug, nil) |> assign(:selected_bug_id, nil)}
  end

  @impl true
  def handle_event("quick_fault", %{"type" => "memory_leak"}, socket) do
    {:ok, _} =
      Coordinator.inject_fault("memory_leak", "user-service", %{
        "growth_rate_mb" => 40,
        "max_memory_mb" => 750
      })

    {:noreply, put_flash(socket, :info, "Injected Memory Leak into User Service.")}
  end

  @impl true
  def handle_event("quick_fault", %{"type" => "service_crash"}, socket) do
    {:ok, _} =
      Coordinator.inject_fault("service_crash", "payment-service", %{"crash_mode" => "sigkill"})

    {:noreply, put_flash(socket, :info, "Crashed Payment Service.")}
  end

  @impl true
  def handle_event("quick_fault", %{"type" => "db_failure"}, socket) do
    {:ok, _} =
      Coordinator.inject_fault("database_failure", "postgres-db", %{
        "mode" => "connection_failure"
      })

    {:noreply, put_flash(socket, :info, "Injected Connection Outage into PostgreSQL Database.")}
  end

  @impl true
  def handle_event("quick_recovery", %{"action" => action, "target" => target}, socket) do
    {:ok, rec} = Coordinator.apply_recovery(action, target)

    msg =
      if rec.success,
        do: "Applied #{action} on #{target}: #{rec.details}",
        else: "Failed to apply #{action}: #{rec.details}"

    {:noreply, put_flash(socket, :info, msg)}
  end

  @impl true
  def handle_event("remedy_bug", %{"bug_id" => bug_id}, socket) do
    state = Coordinator.get_state()
    bug = Map.get(state.bugs, bug_id)

    if bug do
      # Determine action based on bug type
      {action, target} =
        case bug.type do
          "memory_hog" -> {"restart", bug.current_service}
          "crash_worm" -> {"restart", bug.current_service}
          "race_demon" -> {"race_mitigation", bug.current_service}
          "latency_parasite" -> {"circuit_breaker", bug.current_service}
          "packet_phantom" -> {"bounded_retries", bug.current_service}
          "db_gremlin" -> {"cache_fallback", "user-service"}
          _ -> {"restart", bug.current_service}
        end

      {:ok, rec} = Coordinator.apply_recovery(action, target)

      {:noreply,
       socket
       |> assign(:selected_bug_id, nil)
       |> put_flash(:info, "Remedy applied: #{action} on #{target}. #{rec.details}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    LiveHelper.handle_common_event(event, params, socket)
  end

  @impl true
  def handle_info({:simulation_state_updated, state}, socket) do
    {:noreply, assign(socket, :sim_state, state)}
  end

  @impl true
  def handle_info(msg, socket) do
    LiveHelper.handle_sim_info(msg, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_page={@current_page}
      sim_state={@sim_state}
      current_scope={@current_scope}
    >
      <div class="p-6 space-y-6 max-w-[1700px] mx-auto w-full">
        <%!-- Title and Action Bar --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-[#263244]">
          <div>
            <h1 class="text-xl font-bold text-white flex items-center gap-2 tracking-wide">
              <span>SYSTEM COMMAND CENTER</span>
              <span class="inline-block w-2.5 h-2.5 rounded-full bg-cyan-400 animate-ping"></span>
            </h1>
            <p class="text-xs text-slate-400 mt-1">
              Authoritative real-time distributed simulation runtime & living topology
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <button
              phx-click="quick_fault"
              phx-value-type="memory_leak"
              class="px-2.5 py-1.5 rounded bg-[#161E2C] hover:bg-rose-950/40 border border-[#263244] hover:border-rose-500/40 text-slate-300 hover:text-rose-300 text-xs font-medium transition cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-fire" class="w-3.5 h-3.5 text-rose-400" />
              <span>Leak Memory</span>
            </button>

            <button
              phx-click="quick_fault"
              phx-value-type="service_crash"
              class="px-2.5 py-1.5 rounded bg-[#161E2C] hover:bg-rose-950/40 border border-[#263244] hover:border-rose-500/40 text-slate-300 hover:text-rose-300 text-xs font-medium transition cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-bolt-slash" class="w-3.5 h-3.5 text-rose-400" />
              <span>Crash Payment</span>
            </button>

            <button
              phx-click="quick_fault"
              phx-value-type="db_failure"
              class="px-2.5 py-1.5 rounded bg-[#161E2C] hover:bg-rose-950/40 border border-[#263244] hover:border-rose-500/40 text-slate-300 hover:text-rose-300 text-xs font-medium transition cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-server-stack" class="w-3.5 h-3.5 text-rose-400" />
              <span>DB Outage</span>
            </button>

            <.link
              navigate={~p"/faults"}
              class="px-3 py-1.5 rounded bg-cyan-950 hover:bg-cyan-900 border border-cyan-500/40 text-cyan-300 text-xs font-semibold transition cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-plus-circle" class="w-3.5 h-3.5" />
              <span>Fault Lab</span>
            </.link>

            <.link
              navigate={~p"/recovery"}
              class="px-3 py-1.5 rounded bg-emerald-950 hover:bg-emerald-900 border border-emerald-500/40 text-emerald-300 text-xs font-semibold transition cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-shield-check" class="w-3.5 h-3.5" />
              <span>Recoveries</span>
            </.link>
          </div>
        </div>

        <%!-- Compact Metric Cards with Live Indicators --%>
        <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          <div class="p-3.5 rounded-lg bg-[#111722] border border-[#263244] relative overflow-hidden">
            <div class="text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
              Health Score
            </div>
            <div class="flex items-baseline gap-2 mt-1">
              <span class={[
                "text-2xl font-bold tracking-tight",
                @sim_state.global_metrics.health_pct >= 90 && "text-emerald-400",
                (@sim_state.global_metrics.health_pct < 90 and
                   @sim_state.global_metrics.health_pct >= 60) && "text-amber-400",
                @sim_state.global_metrics.health_pct < 60 && "text-rose-400"
              ]}>
                {@sim_state.global_metrics.health_pct}%
              </span>
            </div>
            <div class="text-[10px] text-slate-400 mt-1">
              {@sim_state.global_metrics.healthy_services} healthy / {@sim_state.global_metrics.degraded_services} degraded / {@sim_state.global_metrics.failing_services} failing
            </div>
            <div class="absolute right-2 top-2 opacity-10">
              <.icon name="hero-heart" class="w-10 h-10 text-emerald-400" />
            </div>
          </div>

          <div class="p-3.5 rounded-lg bg-[#111722] border border-[#263244] relative overflow-hidden">
            <div class="text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
              Total Load
            </div>
            <div class="flex items-baseline gap-1 mt-1">
              <span class="text-2xl font-bold tracking-tight text-cyan-300">
                {@sim_state.global_metrics.total_rps}
              </span>
              <span class="text-xs text-slate-400">rps</span>
            </div>
            <div class="text-[10px] text-slate-400 mt-1">
              Synthetic traffic flow
            </div>
            <div class="absolute right-2 top-2 opacity-10">
              <.icon name="hero-arrows-right-left" class="w-10 h-10 text-cyan-400" />
            </div>
          </div>

          <div class="p-3.5 rounded-lg bg-[#111722] border border-[#263244] relative overflow-hidden">
            <div class="text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
              Avg Latency
            </div>
            <div class="flex items-baseline gap-1 mt-1">
              <span class={[
                "text-2xl font-bold tracking-tight",
                @sim_state.global_metrics.avg_latency_ms < 50 && "text-slate-100",
                (@sim_state.global_metrics.avg_latency_ms >= 50 and
                   @sim_state.global_metrics.avg_latency_ms < 150) && "text-amber-400",
                @sim_state.global_metrics.avg_latency_ms >= 150 && "text-rose-400"
              ]}>
                {@sim_state.global_metrics.avg_latency_ms}
              </span>
              <span class="text-xs text-slate-400">ms</span>
            </div>
            <div class="text-[10px] text-slate-400 mt-1">
              p95: {@sim_state.global_metrics.p95_latency_ms} ms
            </div>
            <div class="absolute right-2 top-2 opacity-10">
              <.icon name="hero-clock" class="w-10 h-10 text-slate-300" />
            </div>
          </div>

          <div class="p-3.5 rounded-lg bg-[#111722] border border-[#263244] relative overflow-hidden">
            <div class="text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
              Error Rate
            </div>
            <div class="flex items-baseline gap-1 mt-1">
              <span class={[
                "text-2xl font-bold tracking-tight",
                @sim_state.global_metrics.error_rate < 0.02 && "text-slate-100",
                @sim_state.global_metrics.error_rate >= 0.02 && "text-rose-400"
              ]}>
                {Float.round(@sim_state.global_metrics.error_rate * 100, 2)}%
              </span>
            </div>
            <div class="text-[10px] text-slate-400 mt-1">
              SLO budget: 99.9%
            </div>
            <div class="absolute right-2 top-2 opacity-10">
              <.icon name="hero-exclamation-circle" class="w-10 h-10 text-rose-400" />
            </div>
          </div>

          <div class="p-3.5 rounded-lg bg-[#111722] border border-[#263244] relative overflow-hidden">
            <div class="text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
              Living Bugs
            </div>
            <div class="flex items-baseline gap-2 mt-1">
              <span class="text-2xl font-bold tracking-tight text-amber-400">
                {map_size(@sim_state.bugs)}
              </span>
            </div>
            <div class="text-[10px] text-slate-400 mt-1">
              {Enum.count(@sim_state.bugs, fn {_, b} -> b.status == "propagating" end)} propagating
            </div>
            <div class="absolute right-2 top-2 opacity-10">
              <.icon name="hero-bug-ant" class="w-10 h-10 text-amber-400" />
            </div>
          </div>

          <div class="p-3.5 rounded-lg bg-[#111722] border border-[#263244] relative overflow-hidden">
            <div class="text-[10px] text-slate-400 uppercase tracking-wider font-semibold">
              Active Incidents
            </div>
            <div class="flex items-baseline gap-2 mt-1">
              <span class={[
                "text-2xl font-bold tracking-tight",
                @sim_state.global_metrics.active_incidents_count == 0 && "text-slate-200",
                @sim_state.global_metrics.active_incidents_count > 0 && "text-rose-400 animate-pulse"
              ]}>
                {@sim_state.global_metrics.active_incidents_count}
              </span>
            </div>
            <div class="text-[10px] text-slate-400 mt-1">
              {map_size(@sim_state.incidents)} recorded
            </div>
            <div class="absolute right-2 top-2 opacity-10">
              <.icon name="hero-bell-alert" class="w-10 h-10 text-rose-400" />
            </div>
          </div>
        </div>

        <%!-- Living Topology Canvas (Center Stage) --%>
        <div class="rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-2xl relative">
          <div class="px-5 py-3 border-b border-[#263244] flex items-center justify-between bg-[#161E2C]/50">
            <div class="flex items-center gap-3">
              <span class="text-xs font-bold text-white uppercase tracking-wider flex items-center gap-2">
                <.icon name="hero-circle-stack" class="w-4 h-4 text-cyan-400" />
                Live Service Dependency Graph
              </span>
              <span class="text-[11px] text-slate-400">
                10 nodes · 11 dependency links · Click node or bug for telemetry inspection
              </span>
            </div>

            <div class="flex items-center gap-2 text-xs">
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-emerald-400"></span> Healthy
              </span>
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-amber-400"></span> Degraded
              </span>
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-rose-400"></span> Failing / Offline
              </span>
            </div>
          </div>

          <%!-- SVG Living Graph --%>
          <div class="relative w-full overflow-x-auto bg-[#0A0E18] min-h-[580px] p-2 flex justify-center">
            <svg
              viewBox="0 0 960 540"
              class="w-full max-w-[1000px] h-[540px] select-none"
            >
              <defs>
                <%!-- Marker for dependency arrows --%>
                <marker
                  id="arrow-ok"
                  viewBox="0 0 10 10"
                  refX="28"
                  refY="5"
                  markerWidth="6"
                  markerHeight="6"
                  orient="auto-start-reverse"
                >
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#3B82F6" opacity="0.6" />
                </marker>
                <marker
                  id="arrow-warn"
                  viewBox="0 0 10 10"
                  refX="28"
                  refY="5"
                  markerWidth="6"
                  markerHeight="6"
                  orient="auto-start-reverse"
                >
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#F59E0B" />
                </marker>
                <marker
                  id="arrow-error"
                  viewBox="0 0 10 10"
                  refX="28"
                  refY="5"
                  markerWidth="6"
                  markerHeight="6"
                  orient="auto-start-reverse"
                >
                  <path d="M 0 1 L 10 5 L 0 9 z" fill="#EF4444" />
                </marker>

                <%!-- Radial glow filter --%>
                <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
                  <feGaussianBlur stdDeviation="3" result="blur" />
                  <feComposite in="SourceGraphic" in2="blur" operator="over" />
                </filter>
              </defs>

              <%!-- Draw Dependency Edges --%>
              <%= for dep <- @sim_state.dependencies do %>
                <% src = Map.get(@sim_state.services, dep.source)
                tgt = Map.get(@sim_state.services, dep.target) %>
                <%= if src && tgt do %>
                  <% is_error = tgt.status in ["offline", "failing"] or tgt.error_rate > 0.2
                  is_warn = tgt.status == "degraded" or tgt.error_rate > 0.05

                  stroke_color =
                    cond do
                      is_error -> "#EF4444"
                      is_warn -> "#F59E0B"
                      true -> "#263244"
                    end

                  marker_id =
                    cond do
                      is_error -> "url(#arrow-error)"
                      is_warn -> "url(#arrow-warn)"
                      true -> "url(#arrow-ok)"
                    end %>
                  <g class="transition-all duration-300">
                    <line
                      x1={src.pos_x}
                      y1={src.pos_y}
                      x2={tgt.pos_x}
                      y2={tgt.pos_y}
                      stroke={stroke_color}
                      stroke-width={if(is_error or is_warn, do: "2.5", else: "1.5")}
                      stroke-dasharray={if(dep.critical, do: "none", else: "4,4")}
                      marker-end={marker_id}
                    />

                    <%!-- Edge protocol label --%>
                    <rect
                      x={(src.pos_x + tgt.pos_x) / 2 - 18}
                      y={(src.pos_y + tgt.pos_y) / 2 - 8}
                      width="36"
                      height="16"
                      rx="3"
                      fill="#0C101A"
                      stroke="#263244"
                      stroke-width="1"
                    />
                    <text
                      x={(src.pos_x + tgt.pos_x) / 2}
                      y={(src.pos_y + tgt.pos_y) / 2 + 4}
                      fill="#64748B"
                      font-size="9"
                      font-family="monospace"
                      text-anchor="middle"
                    >
                      {dep.protocol}
                    </text>
                  </g>
                <% end %>
              <% end %>

              <%!-- Draw Animated Traffic Packets --%>
              <%= for pkt <- @sim_state.traffic_packets do %>
                <% src = Map.get(@sim_state.services, pkt.from)
                tgt = Map.get(@sim_state.services, pkt.to) %>
                <%= if src && tgt do %>
                  <% cur_x = src.pos_x + (tgt.pos_x - src.pos_x) * pkt.progress
                  cur_y = src.pos_y + (tgt.pos_y - src.pos_y) * pkt.progress

                  dot_color =
                    case pkt.status do
                      "error" -> "#EF4444"
                      "degraded" -> "#F59E0B"
                      _ -> "#00F0FF"
                    end %>
                  <circle
                    cx={cur_x}
                    cy={cur_y}
                    r="4"
                    fill={dot_color}
                    filter="url(#glow)"
                    opacity="0.95"
                  />
                <% end %>
              <% end %>

              <%!-- Draw Living Bug Entities (Moving/Pulse Organisms) --%>
              <%= for {_bug_id, bug} <- @sim_state.bugs do %>
                <% svc = Map.get(@sim_state.services, bug.current_service) %>
                <%= if svc do %>
                  <g
                    phx-click="select_bug"
                    phx-value-id={bug.id}
                    class="cursor-pointer group transform transition-transform hover:scale-125"
                    filter="url(#glow)"
                  >
                    <%!-- Pulsing aura around bug --%>
                    <circle
                      cx={svc.pos_x + 52}
                      cy={svc.pos_y - 20}
                      r="16"
                      fill={
                        if(bug.status == "contained",
                          do: "rgba(59,130,246,0.25)",
                          else: "rgba(239,68,68,0.3)"
                        )
                      }
                      class="animate-ping"
                    />
                    <circle
                      cx={svc.pos_x + 52}
                      cy={svc.pos_y - 20}
                      r="12"
                      fill={if(bug.status == "contained", do: "#1E3A8A", else: "#881337")}
                      stroke={if(bug.status == "contained", do: "#60A5FA", else: "#F43F5E")}
                      stroke-width="1.5"
                    />
                    <text
                      x={svc.pos_x + 52}
                      y={svc.pos_y - 16}
                      fill="#FFFFFF"
                      font-size="10"
                      font-weight="bold"
                      text-anchor="middle"
                    >
                      👾
                    </text>
                    <%!-- Bug Tag pill --%>
                    <rect
                      x={svc.pos_x + 68}
                      y={svc.pos_y - 28}
                      width="54"
                      height="16"
                      rx="3"
                      fill="#1E1E2E"
                      stroke={if(bug.status == "contained", do: "#3B82F6", else: "#E11D48")}
                      stroke-width="1"
                    />
                    <text
                      x={svc.pos_x + 95}
                      y={svc.pos_y - 17}
                      fill={if(bug.status == "contained", do: "#93C5FD", else: "#FDA4AF")}
                      font-size="9"
                      font-weight="bold"
                      text-anchor="middle"
                    >
                      {bug.code}
                    </text>
                  </g>
                <% end %>
              <% end %>

              <%!-- Draw Service Nodes --%>
              <%= for {_slug, svc} <- @sim_state.services do %>
                <% is_selected = @selected_service_slug == svc.slug

                border_color =
                  case svc.status do
                    "healthy" -> "#10B981"
                    "degraded" -> "#F59E0B"
                    "recovering" -> "#3B82F6"
                    _ -> "#EF4444"
                  end %>
                <g
                  phx-click="select_service"
                  phx-value-slug={svc.slug}
                  class="cursor-pointer transition-transform hover:scale-105"
                >
                  <%!-- Node Box --%>
                  <rect
                    x={svc.pos_x - 70}
                    y={svc.pos_y - 32}
                    width="140"
                    height="64"
                    rx="8"
                    fill={if(is_selected, do: "#1E2738", else: "#111722")}
                    stroke={if(is_selected, do: "#00F0FF", else: border_color)}
                    stroke-width={if(is_selected, do: "2.5", else: "1.5")}
                    filter={
                      if(is_selected or svc.status != "healthy", do: "url(#glow)", else: "none")
                    }
                  />

                  <%!-- Category Badge in Node --%>
                  <rect
                    x={svc.pos_x - 64}
                    y={svc.pos_y - 26}
                    width="44"
                    height="12"
                    rx="2"
                    fill="#161E2C"
                  />
                  <text
                    x={svc.pos_x - 42}
                    y={svc.pos_y - 17}
                    fill="#94A3B8"
                    font-size="8"
                    font-family="monospace"
                    text-anchor="middle"
                  >
                    {String.upcase(svc.category)}
                  </text>

                  <%!-- Status Dot --%>
                  <circle
                    cx={svc.pos_x + 56}
                    cy={svc.pos_y - 20}
                    r="4"
                    fill={border_color}
                  />

                  <%!-- Service Name --%>
                  <text
                    x={svc.pos_x - 64}
                    y={svc.pos_y + 2}
                    fill="#F1F5F9"
                    font-size="11"
                    font-weight="bold"
                    font-family="monospace"
                  >
                    {svc.name}
                  </text>

                  <%!-- Live Resource Bars / Metrics --%>
                  <text
                    x={svc.pos_x - 64}
                    y={svc.pos_y + 20}
                    fill="#94A3B8"
                    font-size="9"
                    font-family="monospace"
                  >
                    {svc.latency_ms}ms · {round(svc.cpu_pct)}% cpu · {round(svc.error_rate * 100)}% err
                  </text>
                </g>
              <% end %>
            </svg>
          </div>
        </div>

        <%!-- Slide-Over Drawer for Selected Service Inspection --%>
        <%= if @selected_service_slug do %>
          <% svc = Map.get(@sim_state.services, @selected_service_slug) %>
          <%= if svc do %>
            <div class="rounded-xl bg-[#111722] border border-cyan-500/40 p-5 shadow-2xl relative">
              <div class="flex items-start justify-between pb-4 border-b border-[#263244]">
                <div>
                  <div class="flex items-center gap-3">
                    <h2 class="text-lg font-bold text-white">{svc.name}</h2>
                    <span class={[
                      "px-2 py-0.5 rounded text-xs font-semibold uppercase tracking-wider",
                      svc.status == "healthy" &&
                        "bg-emerald-950 border border-emerald-500/40 text-emerald-400",
                      svc.status == "degraded" &&
                        "bg-amber-950 border border-amber-500/40 text-amber-400",
                      svc.status in ["failing", "offline"] &&
                        "bg-rose-950 border border-rose-500/40 text-rose-400 animate-pulse"
                    ]}>
                      {svc.status}
                    </span>
                  </div>
                  <p class="text-xs text-slate-400 mt-1">Slug: {svc.slug} · Type: {svc.category}</p>
                </div>

                <button
                  phx-click="close_drawer"
                  class="text-slate-400 hover:text-white text-xs px-2 py-1 rounded bg-[#161E2C] border border-[#263244] cursor-pointer"
                >
                  Close ✕
                </button>
              </div>

              <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 my-4 text-xs">
                <div class="p-3 rounded bg-[#161E2C] border border-[#263244]">
                  <span class="text-slate-400 text-[10px] uppercase">Latency</span>
                  <div class="text-base font-bold text-slate-100 mt-1">{svc.latency_ms} ms</div>
                  <span class="text-[10px] text-slate-500">Baseline: {svc.baseline_latency_ms} ms</span>
                </div>

                <div class="p-3 rounded bg-[#161E2C] border border-[#263244]">
                  <span class="text-slate-400 text-[10px] uppercase">Error Rate</span>
                  <div class="text-base font-bold text-rose-400 mt-1">
                    {Float.round(svc.error_rate * 100, 2)}%
                  </div>
                  <span class="text-[10px] text-slate-500">Baseline: {Float.round(
                    svc.baseline_error_rate * 100,
                    2
                  )}%</span>
                </div>

                <div class="p-3 rounded bg-[#161E2C] border border-[#263244]">
                  <span class="text-slate-400 text-[10px] uppercase">CPU Load</span>
                  <div class="text-base font-bold text-cyan-300 mt-1">
                    {Float.round(svc.cpu_pct, 1)}%
                  </div>
                  <span class="text-[10px] text-slate-500">Baseline: {svc.baseline_cpu}%</span>
                </div>

                <div class="p-3 rounded bg-[#161E2C] border border-[#263244]">
                  <span class="text-slate-400 text-[10px] uppercase">Memory Heap</span>
                  <div class="text-base font-bold text-amber-300 mt-1">{svc.memory_mb} MB</div>
                  <span class="text-[10px] text-slate-500">Baseline: {svc.baseline_memory_mb} MB</span>
                </div>
              </div>

              <div class="flex flex-wrap items-center gap-2 pt-2 border-t border-[#263244]">
                <span class="text-xs text-slate-400 font-semibold mr-2">Quick Actions:</span>
                <button
                  phx-click="quick_recovery"
                  phx-value-action="restart"
                  phx-value-target={svc.slug}
                  class="px-3 py-1.5 rounded bg-emerald-950/80 hover:bg-emerald-900 border border-emerald-500/40 text-emerald-300 text-xs font-semibold cursor-pointer"
                >
                  Restart Service
                </button>

                <button
                  phx-click="quick_recovery"
                  phx-value-action="circuit_breaker"
                  phx-value-target={svc.slug}
                  class="px-3 py-1.5 rounded bg-cyan-950/80 hover:bg-cyan-900 border border-cyan-500/40 text-cyan-300 text-xs font-semibold cursor-pointer"
                >
                  Enable Circuit Breaker
                </button>

                <button
                  phx-click="quick_recovery"
                  phx-value-action="adjust_timeout"
                  phx-value-target={svc.slug}
                  class="px-3 py-1.5 rounded bg-indigo-950/80 hover:bg-indigo-900 border border-indigo-500/40 text-indigo-300 text-xs font-semibold cursor-pointer"
                >
                  Calibrate Timeouts
                </button>
              </div>
            </div>
          <% end %>
        <% end %>

        <%!-- Modal Inspector for Living Bug Entity --%>
        <%= if @selected_bug_id do %>
          <% bug = Map.get(@sim_state.bugs, @selected_bug_id) %>
          <%= if bug do %>
            <div class="rounded-xl bg-[#111722] border border-rose-500/50 p-5 shadow-2xl relative">
              <div class="flex items-start justify-between pb-3 border-b border-[#263244]">
                <div class="flex items-center gap-3">
                  <span class="text-2xl">👾</span>
                  <div>
                    <h3 class="text-base font-bold text-white flex items-center gap-2">
                      <span>LIVING BUG ENTITY: {bug.code}</span>
                      <span class="px-2 py-0.5 rounded text-[11px] bg-rose-950 border border-rose-500/50 text-rose-300 font-mono">
                        {String.upcase(bug.type)}
                      </span>
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Originating: {bug.originating_service} · Current Location: {bug.current_service} · Status: {bug.status}
                    </p>
                  </div>
                </div>

                <button
                  phx-click="close_drawer"
                  class="text-slate-400 hover:text-white text-xs px-2 py-1 rounded bg-[#161E2C] border border-[#263244] cursor-pointer"
                >
                  Close ✕
                </button>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 my-4 text-xs">
                <div>
                  <h4 class="font-bold text-slate-300 mb-2">Propagation Lineage History:</h4>
                  <div class="space-y-1.5 max-h-40 overflow-y-auto">
                    <%= for event <- bug.history do %>
                      <div class="p-2 rounded bg-[#161E2C] border border-[#263244] text-slate-300">
                        <span class="text-cyan-400 font-semibold">{event.service}:</span> {event.event}
                      </div>
                    <% end %>
                  </div>
                </div>

                <div>
                  <h4 class="font-bold text-slate-300 mb-2">Diagnostics & Recommended Remedy:</h4>
                  <div class="p-3 rounded bg-amber-950/20 border border-amber-500/30 text-amber-200 space-y-2">
                    <p><strong>Impact Score:</strong> {bug.impact_score} / 100</p>
                    <p><strong>Remedy Strategy:</strong> {bug.suggested_remedy}</p>
                    <button
                      phx-click="remedy_bug"
                      phx-value-bug_id={bug.id}
                      class="w-full mt-2 py-2 rounded bg-emerald-600 hover:bg-emerald-500 text-white font-bold transition shadow-lg cursor-pointer"
                    >
                      Apply Recommended Remedy Now
                    </button>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>

        <%!-- Live Incident Feed & Event Timeline --%>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Live Incidents List --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-lg flex flex-col">
            <div class="px-4 py-3 border-b border-[#263244] bg-[#161E2C]/60 flex items-center justify-between">
              <span class="text-xs font-bold text-slate-200 uppercase tracking-wider flex items-center gap-2">
                <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-rose-400" />
                Active Incident Stream
              </span>
              <.link navigate={~p"/incidents"} class="text-xs text-cyan-400 hover:text-cyan-300">
                View All &rarr;
              </.link>
            </div>

            <div class="p-4 space-y-2.5 flex-1 max-h-80 overflow-y-auto">
              <%= if map_size(@sim_state.incidents) == 0 do %>
                <div class="text-center py-8 text-xs text-slate-500">
                  <.icon name="hero-check-badge" class="w-8 h-8 text-emerald-500/40 mx-auto mb-2" />
                  No open incidents. All operational thresholds healthy.
                </div>
              <% else %>
                <%= for {_id, inc} <- @sim_state.incidents do %>
                  <div class={[
                    "p-3 rounded-lg border text-xs flex items-start justify-between gap-3 transition",
                    inc.status in ["open", "investigating"] && "bg-rose-950/30 border-rose-500/40",
                    inc.status == "mitigating" && "bg-amber-950/30 border-amber-500/40",
                    inc.status == "resolved" && "bg-[#161E2C] border-[#263244] opacity-75"
                  ]}>
                    <div class="space-y-1">
                      <div class="flex items-center gap-2">
                        <span class="font-bold text-white font-mono">{inc.code}</span>
                        <span class="px-1.5 py-0.2 rounded text-[10px] uppercase font-semibold bg-[#0C101A] text-rose-300 border border-rose-500/30">
                          {inc.severity}
                        </span>
                        <span class="text-[10px] text-slate-400">{inc.status}</span>
                      </div>
                      <p class="text-slate-200 font-medium">{inc.title}</p>
                      <div class="text-[10px] text-slate-400">
                        Affected: {Enum.join(inc.affected_services, ", ")}
                      </div>
                    </div>

                    <.link
                      navigate={~p"/incidents"}
                      class="shrink-0 px-2.5 py-1 rounded bg-[#161E2C] hover:bg-[#202B3D] text-[11px] text-cyan-400 border border-[#263244]"
                    >
                      Investigate
                    </.link>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Event Timeline / Logs Stream --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-lg flex flex-col">
            <div class="px-4 py-3 border-b border-[#263244] bg-[#161E2C]/60 flex items-center justify-between">
              <span class="text-xs font-bold text-slate-200 uppercase tracking-wider flex items-center gap-2">
                <.icon name="hero-queue-list" class="w-4 h-4 text-cyan-400" />
                Live Event Timeline & Telemetry
              </span>
              <.link navigate={~p"/observability"} class="text-xs text-cyan-400 hover:text-cyan-300">
                Observability &rarr;
              </.link>
            </div>

            <div class="p-3 space-y-1.5 flex-1 max-h-80 overflow-y-auto font-mono text-[11px]">
              <%= for log <- Enum.take(@sim_state.recent_logs, 25) do %>
                <div class="flex items-start gap-2 py-1 px-2 rounded hover:bg-[#161E2C]">
                  <span class="text-slate-400 text-[10px] shrink-0">{Calendar.strftime(
                    log.timestamp,
                    "%H:%M:%S"
                  )}</span>
                  <span class={[
                    "px-1 py-0.2 rounded text-[9px] uppercase font-bold shrink-0",
                    log.severity == "fatal" && "bg-rose-950 text-rose-300 border border-rose-600/40",
                    log.severity == "error" && "bg-red-950 text-red-400 border border-red-600/30",
                    log.severity == "warn" && "bg-amber-950 text-amber-300 border border-amber-600/30",
                    log.severity == "info" && "bg-cyan-950 text-cyan-300 border border-cyan-600/30"
                  ]}>
                    {log.severity}
                  </span>
                  <span class="text-slate-400 font-semibold shrink-0">{log.service_name}:</span>
                  <span class="text-slate-200 truncate">{log.message}</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
