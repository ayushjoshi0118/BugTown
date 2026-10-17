defmodule BugTownWeb.ObservabilityLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveHelper.setup_sim(:observability, "Observability · BugTown")
      # "metrics", "logs", "traces"
      |> assign(:active_tab, "metrics")
      |> assign(:log_search, "")
      |> assign(:log_severity_filter, "all")
      |> assign(:selected_trace_id, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("search_logs", %{"query" => query}, socket) do
    {:noreply, assign(socket, :log_search, query)}
  end

  @impl true
  def handle_event("filter_severity", %{"severity" => sev}, socket) do
    {:noreply, assign(socket, :log_severity_filter, sev)}
  end

  @impl true
  def handle_event("select_trace", %{"id" => id}, socket) do
    current = socket.assigns.selected_trace_id
    new_sel = if current == id, do: nil, else: id
    {:noreply, assign(socket, :selected_trace_id, new_sel)}
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
    filtered_logs =
      assigns.sim_state.recent_logs
      |> Enum.filter(fn l ->
        match_sev =
          assigns.log_severity_filter == "all" or l.severity == assigns.log_severity_filter

        match_search =
          assigns.log_search == "" or
            String.contains?(String.downcase(l.message), String.downcase(assigns.log_search)) or
            String.contains?(String.downcase(l.service_name), String.downcase(assigns.log_search))

        match_sev and match_search
      end)

    assigns = assign(assigns, :filtered_logs, filtered_logs)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_page={@current_page}
      sim_state={@sim_state}
      current_scope={@current_scope}
    >
      <div class="p-6 space-y-6 max-w-[1700px] mx-auto w-full">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-[#263244]">
          <div>
            <h1 class="text-xl font-bold text-white flex items-center gap-2">
              <.icon name="hero-chart-bar" class="w-5 h-5 text-cyan-400" />
              <span>SIMULATED OBSERVABILITY SUITE</span>
            </h1>
            <p class="text-xs text-slate-400 mt-1">
              Time-series metrics, structured telemetry logs, and distributed request waterfall traces
            </p>
          </div>

          <%!-- Navigation Tabs --%>
          <div class="flex items-center bg-[#111722] border border-[#263244] rounded p-1 text-xs">
            <button
              phx-click="set_tab"
              phx-value-tab="metrics"
              class={[
                "px-3 py-1.5 rounded cursor-pointer font-bold transition flex items-center gap-1.5",
                @active_tab == "metrics" && "bg-cyan-500/20 text-cyan-300 shadow"
              ]}
            >
              <.icon name="hero-presentation-chart-line" class="w-4 h-4" />
              <span>Metrics</span>
            </button>
            <button
              phx-click="set_tab"
              phx-value-tab="logs"
              class={[
                "px-3 py-1.5 rounded cursor-pointer font-bold transition flex items-center gap-1.5",
                @active_tab == "logs" && "bg-cyan-500/20 text-cyan-300 shadow"
              ]}
            >
              <.icon name="hero-document-text" class="w-4 h-4" />
              <span>Structured Logs</span>
            </button>
            <button
              phx-click="set_tab"
              phx-value-tab="traces"
              class={[
                "px-3 py-1.5 rounded cursor-pointer font-bold transition flex items-center gap-1.5",
                @active_tab == "traces" && "bg-cyan-500/20 text-cyan-300 shadow"
              ]}
            >
              <.icon name="hero-queue-list" class="w-4 h-4" />
              <span>Distributed Traces</span>
            </button>
          </div>
        </div>

        <%!-- TAB 1: METRICS TIME-SERIES --%>
        <%= if @active_tab == "metrics" do %>
          <% history = Enum.reverse(@sim_state.history_metrics)
          # Build points for sparkline polyline SVG
          max_points = max(2, length(history))
          svg_width = 400
          svg_height = 90

          build_points = fn values, min_val, max_val ->
            range = max(1.0, max_val - min_val)

            values
            |> Enum.with_index()
            |> Enum.map(fn {v, idx} ->
              x = idx / (max_points - 1) * svg_width
              norm_y = (v - min_val) / range
              y = svg_height - (norm_y * (svg_height - 15) + 5)
              "#{Float.round(x, 1)},#{Float.round(y, 1)}"
            end)
            |> Enum.join(" ")
          end %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%!-- Latency Card --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-slate-200">Request Latency (Avg & p95)</span>
                <span class="font-mono text-cyan-400 font-bold">{@sim_state.global_metrics.avg_latency_ms} ms</span>
              </div>
              <div class="h-24 w-full bg-[#0C101A] rounded border border-[#263244] flex items-center justify-center p-2">
                <svg viewBox={"0 0 #{svg_width} #{svg_height}"} class="w-full h-full overflow-visible">
                  <% lats = Enum.map(history, & &1.avg_latency_ms)
                  points = build_points.(lats, 0, max(100.0, Enum.max(lats ++ [100.0]))) %>
                  <polyline
                    fill="none"
                    stroke="#00F0FF"
                    stroke-width="2"
                    stroke-linecap="round"
                    points={points}
                  />
                </svg>
              </div>
              <div class="text-[10px] text-slate-400 flex justify-between">
                <span>p95 Latency: {@sim_state.global_metrics.p95_latency_ms} ms</span>
                <span>Rolling 60 ticks</span>
              </div>
            </div>

            <%!-- Error Rate Card --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-slate-200">Error Rate (%)</span>
                <span class={[
                  "font-mono font-bold",
                  @sim_state.global_metrics.error_rate > 0.05 && "text-rose-400",
                  @sim_state.global_metrics.error_rate <= 0.05 && "text-emerald-400"
                ]}>
                  {Float.round(@sim_state.global_metrics.error_rate * 100, 2)}%
                </span>
              </div>
              <div class="h-24 w-full bg-[#0C101A] rounded border border-[#263244] flex items-center justify-center p-2">
                <svg viewBox={"0 0 #{svg_width} #{svg_height}"} class="w-full h-full overflow-visible">
                  <% errs = Enum.map(history, &(&1.error_rate * 100))
                  points = build_points.(errs, 0, max(5.0, Enum.max(errs ++ [5.0]))) %>
                  <polyline
                    fill="none"
                    stroke="#F43F5E"
                    stroke-width="2"
                    stroke-linecap="round"
                    points={points}
                  />
                </svg>
              </div>
              <div class="text-[10px] text-slate-400 flex justify-between">
                <span>SLO threshold: 1.0%</span>
                <span>Rolling 60 ticks</span>
              </div>
            </div>

            <%!-- Throughput RPS Card --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-slate-200">System Throughput (RPS)</span>
                <span class="font-mono text-cyan-300 font-bold">{@sim_state.global_metrics.total_rps} req/s</span>
              </div>
              <div class="h-24 w-full bg-[#0C101A] rounded border border-[#263244] flex items-center justify-center p-2">
                <svg viewBox={"0 0 #{svg_width} #{svg_height}"} class="w-full h-full overflow-visible">
                  <% rpss = Enum.map(history, & &1.total_rps)
                  points = build_points.(rpss, 0, max(180.0, Enum.max(rpss ++ [180.0]))) %>
                  <polyline
                    fill="none"
                    stroke="#10B981"
                    stroke-width="2"
                    stroke-linecap="round"
                    points={points}
                  />
                </svg>
              </div>
              <div class="text-[10px] text-slate-400 flex justify-between">
                <span>Peak capacity: 5000 rps</span>
                <span>Rolling 60 ticks</span>
              </div>
            </div>

            <%!-- Availability Score Card --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-slate-200">System Availability</span>
                <span class="font-mono text-emerald-400 font-bold">{@sim_state.global_metrics.health_pct}%</span>
              </div>
              <div class="h-24 w-full bg-[#0C101A] rounded border border-[#263244] flex items-center justify-center p-2">
                <svg viewBox={"0 0 #{svg_width} #{svg_height}"} class="w-full h-full overflow-visible">
                  <% avails = Enum.map(history, & &1.health_pct)
                  points = build_points.(avails, 0, 100.0) %>
                  <polyline
                    fill="none"
                    stroke="#34D399"
                    stroke-width="2"
                    stroke-linecap="round"
                    points={points}
                  />
                </svg>
              </div>
              <div class="text-[10px] text-slate-400 flex justify-between">
                <span>Healthy nodes: {@sim_state.global_metrics.healthy_services} / 10</span>
                <span>Rolling 60 ticks</span>
              </div>
            </div>

            <%!-- Memory Pressure Breakdown Card --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-slate-200">Cluster Memory Pressure</span>
                <% total_mem = Enum.sum(Enum.map(Map.values(@sim_state.services), & &1.memory_mb)) %>
                <span class="font-mono text-amber-300 font-bold">{total_mem} MB</span>
              </div>
              <div class="space-y-1.5 pt-2">
                <%= for {_slug, svc} <- Enum.take(@sim_state.services, 4) do %>
                  <div class="flex items-center justify-between text-[11px]">
                    <span class="text-slate-400 truncate">{svc.name}</span>
                    <span class="text-white font-mono">{svc.memory_mb} MB</span>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- CPU Utilization Breakdown Card --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-slate-200">Cluster Compute Utilization</span>
                <% avg_cpu =
                  Float.round(
                    Enum.sum(Enum.map(Map.values(@sim_state.services), & &1.cpu_pct)) / 10.0,
                    1
                  ) %>
                <span class="font-mono text-cyan-300 font-bold">{avg_cpu}% Avg</span>
              </div>
              <div class="space-y-1.5 pt-2">
                <%= for {_slug, svc} <- Enum.take(Enum.drop(@sim_state.services, 4), 4) do %>
                  <div class="flex items-center justify-between text-[11px]">
                    <span class="text-slate-400 truncate">{svc.name}</span>
                    <span class="text-white font-mono">{Float.round(svc.cpu_pct, 1)}%</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- TAB 2: STRUCTURED LOGS --%>
        <%= if @active_tab == "logs" do %>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-4">
            <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
              <div class="flex items-center gap-2 w-full sm:w-auto">
                <input
                  type="text"
                  placeholder="Search log messages, services, or events..."
                  value={@log_search}
                  phx-keyup="search_logs"
                  phx-key="Enter"
                  name="query"
                  class="bg-[#161E2C] border border-[#263244] rounded px-3 py-1.5 text-xs text-white w-full sm:w-72 focus:outline-none focus:border-cyan-400"
                />
              </div>

              <div class="flex items-center gap-1 text-xs">
                <%= for sev <- ["all", "fatal", "error", "warn", "info"] do %>
                  <button
                    phx-click="filter_severity"
                    phx-value-severity={sev}
                    class={[
                      "px-2.5 py-1 rounded capitalize font-semibold cursor-pointer",
                      @log_severity_filter == sev &&
                        "bg-cyan-500/20 text-cyan-300 border border-cyan-500/40"
                    ]}
                  >
                    {sev}
                  </button>
                <% end %>
              </div>
            </div>

            <div class="rounded-lg bg-[#0A0E18] border border-[#263244] p-3 max-h-[550px] overflow-y-auto font-mono text-[11px] divide-y divide-[#161E2C]">
              <%= if @filtered_logs == [] do %>
                <div class="p-8 text-center text-slate-500">No logs found matching filter.</div>
              <% else %>
                <%= for log <- @filtered_logs do %>
                  <div class="py-2 flex items-start gap-3 hover:bg-[#111722]/60 px-2 rounded">
                    <span class="text-slate-500 text-[10px] shrink-0">{Calendar.strftime(
                      log.timestamp,
                      "%H:%M:%S.%f"
                    )
                    |> String.slice(0..11)}</span>
                    <span class={[
                      "px-1.5 py-0.2 rounded text-[9px] uppercase font-bold shrink-0",
                      log.severity == "fatal" && "bg-rose-950 text-rose-300 border border-rose-600/40",
                      log.severity == "error" && "bg-red-950 text-red-400 border border-red-600/30",
                      log.severity == "warn" &&
                        "bg-amber-950 text-amber-300 border border-amber-600/30",
                      log.severity == "info" && "bg-cyan-950 text-cyan-300 border border-cyan-600/30"
                    ]}>
                      {log.severity}
                    </span>
                    <span class="text-cyan-400 font-semibold shrink-0">[{log.service_name}]</span>
                    <span class="text-slate-400 shrink-0 font-mono text-[10px]">{log.correlation_id}</span>
                    <span class="text-slate-200 flex-1">{log.message}</span>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <%!-- TAB 3: DISTRIBUTED TRACES (WATERFALL VIEW) --%>
        <%= if @active_tab == "traces" do %>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <%!-- Trace Selection List --%>
            <div class="rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-xl">
              <div class="px-4 py-3 border-b border-[#263244] bg-[#161E2C]/50 text-xs font-bold text-slate-200 uppercase tracking-wider">
                Recent Request Traces ({length(@sim_state.recent_traces)})
              </div>

              <div class="divide-y divide-[#263244] max-h-[580px] overflow-y-auto text-xs">
                <%= if @sim_state.recent_traces == [] do %>
                  <div class="p-8 text-center text-slate-500">Generating initial traces...</div>
                <% else %>
                  <%= for trace <- @sim_state.recent_traces do %>
                    <% is_sel =
                      @selected_trace_id == trace.trace_id or
                        (@selected_trace_id == nil and trace == List.first(@sim_state.recent_traces)) %>
                    <div
                      phx-click="select_trace"
                      phx-value-id={trace.trace_id}
                      class={[
                        "p-3.5 cursor-pointer transition flex items-center justify-between",
                        is_sel && "bg-[#1E2738] border-l-4 border-l-cyan-400",
                        not is_sel && "hover:bg-[#161E2C] border-l-4 border-l-transparent"
                      ]}
                    >
                      <div class="space-y-1">
                        <div class="flex items-center gap-2">
                          <span class="font-mono font-bold text-slate-200">{trace.trace_id}</span>
                          <span class={[
                            "px-1.5 py-0.2 rounded text-[10px] uppercase font-bold",
                            trace.status == "ok" &&
                              "bg-emerald-950 text-emerald-400 border border-emerald-500/30",
                            trace.status == "degraded" &&
                              "bg-amber-950 text-amber-400 border border-amber-500/30",
                            trace.status == "error" &&
                              "bg-rose-950 text-rose-400 border border-rose-500/30"
                          ]}>
                            {trace.status}
                          </span>
                        </div>
                        <div class="text-[11px] text-slate-400 truncate">{trace.path_name}</div>
                      </div>
                      <div class="text-right text-[11px] font-mono font-bold text-cyan-300">
                        {trace.duration_ms} ms
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Trace Waterfall Visualizer (Right 2 cols) --%>
            <div class="lg:col-span-2 rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl flex flex-col justify-between">
              <% active_trace =
                if @selected_trace_id do
                  Enum.find(@sim_state.recent_traces, &(&1.trace_id == @selected_trace_id))
                else
                  List.first(@sim_state.recent_traces)
                end %>
              <%= if active_trace do %>
                <div class="space-y-4">
                  <div class="pb-3 border-b border-[#263244] flex items-center justify-between">
                    <div>
                      <div class="flex items-center gap-2">
                        <span class="font-mono text-sm font-bold text-cyan-400">{active_trace.trace_id}</span>
                        <span class="text-xs text-slate-300 font-semibold">{active_trace.path_name}</span>
                      </div>
                      <div class="text-[11px] text-slate-400 mt-0.5">
                        Root Service: {active_trace.root_service} · Spans: {length(active_trace.spans)}
                      </div>
                    </div>

                    <div class="text-right">
                      <span class="text-base font-bold font-mono text-cyan-300">{active_trace.duration_ms} ms</span>
                    </div>
                  </div>

                  <%!-- Waterfall Spans Timeline --%>
                  <div class="space-y-2 max-h-[460px] overflow-y-auto">
                    <%= for span <- active_trace.spans do %>
                      <% pct_width =
                        min(
                          100.0,
                          max(5.0, span.duration_ms / max(1.0, active_trace.duration_ms) * 100.0)
                        )

                      pct_offset =
                        min(90.0, span.start_offset_ms / max(1.0, active_trace.duration_ms) * 100.0)

                      bar_color =
                        case span.status do
                          "error" -> "bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.4)]"
                          "degraded" -> "bg-amber-500"
                          _ -> "bg-cyan-500"
                        end %>
                      <div class="p-2.5 rounded bg-[#161E2C] border border-[#263244] text-xs space-y-1.5">
                        <div class="flex items-center justify-between">
                          <span class="font-bold text-white flex items-center gap-2">
                            <.icon name="hero-cube" class="w-3.5 h-3.5 text-cyan-400" />
                            {span.service_name}
                            <span class="text-[10px] text-slate-400 font-normal">({span.operation})</span>
                          </span>
                          <span class="font-mono font-bold text-slate-300">{span.duration_ms} ms</span>
                        </div>

                        <%!-- Waterfall Bar --%>
                        <div class="w-full bg-[#0C101A] h-2.5 rounded-full overflow-hidden relative">
                          <div
                            class={["h-full rounded-full transition-all", bar_color]}
                            style={"margin-left: #{pct_offset}%; width: #{pct_width}%;"}
                          >
                          </div>
                        </div>

                        <%= if span.error_details do %>
                          <div class="text-[10px] text-rose-400 font-semibold bg-rose-950/40 p-1 rounded border border-rose-500/30">
                            Failure: {span.error_details}
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <div class="text-center py-20 text-slate-500 text-xs">
                  Select a distributed trace to view its span execution waterfall.
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
