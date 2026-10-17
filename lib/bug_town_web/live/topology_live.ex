defmodule BugTownWeb.TopologyLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveHelper.setup_sim(:topology, "Topology Explorer · BugTown")
      |> assign(:selected_slug, nil)
      |> assign(:filter_category, "all")
      |> assign(:filter_health, "all")
      |> assign(:show_traffic, true)
      |> assign(:zoom_scale, 1.0)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_node", %{"slug" => slug}, socket) do
    current = socket.assigns.selected_slug
    new_sel = if current == slug, do: nil, else: slug
    {:noreply, assign(socket, :selected_slug, new_sel)}
  end

  @impl true
  def handle_event("set_filter_category", %{"category" => cat}, socket) do
    {:noreply, assign(socket, :filter_category, cat)}
  end

  @impl true
  def handle_event("set_filter_health", %{"health" => health}, socket) do
    {:noreply, assign(socket, :filter_health, health)}
  end

  @impl true
  def handle_event("toggle_traffic", _params, socket) do
    {:noreply, assign(socket, :show_traffic, not socket.assigns.show_traffic)}
  end

  @impl true
  def handle_event("zoom_in", _params, socket) do
    {:noreply, assign(socket, :zoom_scale, min(1.6, socket.assigns.zoom_scale + 0.15))}
  end

  @impl true
  def handle_event("zoom_out", _params, socket) do
    {:noreply, assign(socket, :zoom_scale, max(0.6, socket.assigns.zoom_scale - 0.15))}
  end

  @impl true
  def handle_event("zoom_reset", _params, socket) do
    {:noreply, assign(socket, :zoom_scale, 1.0)}
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
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-[#263244]">
          <div>
            <h1 class="text-xl font-bold text-white flex items-center gap-2">
              <.icon name="hero-share" class="w-5 h-5 text-cyan-400" />
              <span>TOPOLOGY EXPLORER</span>
            </h1>
            <p class="text-xs text-slate-400 mt-1">
              Interactive distributed dependency architecture, traffic paths, and cascading failure isolation
            </p>
          </div>

          <%!-- Filters and Viewport Controls --%>
          <div class="flex flex-wrap items-center gap-2 text-xs">
            <%!-- Category filter --%>
            <div class="flex items-center bg-[#111722] border border-[#263244] rounded p-0.5">
              <%= for cat <- ["all", "service", "database", "cache", "queue", "worker"] do %>
                <button
                  phx-click="set_filter_category"
                  phx-value-category={cat}
                  class={[
                    "px-2 py-1 rounded cursor-pointer capitalize",
                    @filter_category == cat && "bg-cyan-500/20 text-cyan-300 font-bold"
                  ]}
                >
                  {cat}
                </button>
              <% end %>
            </div>

            <%!-- Traffic Toggle --%>
            <button
              phx-click="toggle_traffic"
              class={[
                "px-2.5 py-1 rounded border cursor-pointer",
                @show_traffic && "bg-cyan-950/60 border-cyan-500/40 text-cyan-300",
                not @show_traffic && "bg-[#111722] border-[#263244] text-slate-400"
              ]}
            >
              Traffic: {if @show_traffic, do: "ON", else: "OFF"}
            </button>

            <%!-- Zoom controls --%>
            <div class="flex items-center bg-[#111722] border border-[#263244] rounded p-0.5">
              <button
                phx-click="zoom_out"
                class="px-2 py-1 hover:text-white cursor-pointer"
                title="Zoom Out"
              >-</button>
              <button
                phx-click="zoom_reset"
                class="px-2 py-1 text-[11px] font-mono hover:text-white cursor-pointer"
                title="Reset Zoom"
              >
                {round(@zoom_scale * 100)}%
              </button>
              <button
                phx-click="zoom_in"
                class="px-2 py-1 hover:text-white cursor-pointer"
                title="Zoom In"
              >+</button>
            </div>
          </div>
        </div>

        <%!-- Main Topology Layout: Graph on left, Inspector on right --%>
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
          <%!-- SVG Graph Canvas --%>
          <div class="lg:col-span-3 rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-2xl relative">
            <div class="w-full overflow-auto bg-[#0A0E18] min-h-[620px] p-4 flex justify-center">
              <div style={"transform: scale(#{@zoom_scale}); transform-origin: center top; transition: transform 0.2s;"}>
                <svg viewBox="0 0 960 540" class="w-[960px] h-[540px] select-none">
                  <defs>
                    <marker
                      id="topo-arrow"
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
                      id="topo-arrow-err"
                      viewBox="0 0 10 10"
                      refX="28"
                      refY="5"
                      markerWidth="6"
                      markerHeight="6"
                      orient="auto-start-reverse"
                    >
                      <path d="M 0 1 L 10 5 L 0 9 z" fill="#EF4444" />
                    </marker>
                    <filter id="topo-glow" x="-20%" y="-20%" width="140%" height="140%">
                      <feGaussianBlur stdDeviation="3" result="blur" />
                      <feComposite in="SourceGraphic" in2="blur" operator="over" />
                    </filter>
                  </defs>

                  <%!-- Edges --%>
                  <%= for dep <- @sim_state.dependencies do %>
                    <% src = Map.get(@sim_state.services, dep.source)
                    tgt = Map.get(@sim_state.services, dep.target) %>
                    <%= if src && tgt do %>
                      <% is_err = tgt.status in ["offline", "failing"]
                      is_highlighted = @selected_slug == src.slug or @selected_slug == tgt.slug %>
                      <line
                        x1={src.pos_x}
                        y1={src.pos_y}
                        x2={tgt.pos_x}
                        y2={tgt.pos_y}
                        stroke={
                          if(is_err,
                            do: "#EF4444",
                            else: if(is_highlighted, do: "#00F0FF", else: "#263244")
                          )
                        }
                        stroke-width={if(is_highlighted, do: "3", else: "1.5")}
                        marker-end={if(is_err, do: "url(#topo-arrow-err)", else: "url(#topo-arrow)")}
                      />
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
                        text-anchor="middle"
                      >
                        {dep.protocol}
                      </text>
                    <% end %>
                  <% end %>

                  <%!-- Animated Packets if enabled --%>
                  <%= if @show_traffic do %>
                    <%= for pkt <- @sim_state.traffic_packets do %>
                      <% src = Map.get(@sim_state.services, pkt.from)
                      tgt = Map.get(@sim_state.services, pkt.to) %>
                      <%= if src && tgt do %>
                        <circle
                          cx={src.pos_x + (tgt.pos_x - src.pos_x) * pkt.progress}
                          cy={src.pos_y + (tgt.pos_y - src.pos_y) * pkt.progress}
                          r="4"
                          fill={if(pkt.status == "error", do: "#EF4444", else: "#00F0FF")}
                          filter="url(#topo-glow)"
                        />
                      <% end %>
                    <% end %>
                  <% end %>

                  <%!-- Nodes --%>
                  <%= for {_slug, svc} <- @sim_state.services do %>
                    <% is_match_cat = @filter_category == "all" or svc.category == @filter_category
                    is_selected = @selected_slug == svc.slug

                    color =
                      case svc.status do
                        "healthy" -> "#10B981"
                        "degraded" -> "#F59E0B"
                        _ -> "#EF4444"
                      end %>
                    <g
                      phx-click="select_node"
                      phx-value-slug={svc.slug}
                      class="cursor-pointer transition hover:scale-105"
                      opacity={if(is_match_cat, do: "1.0", else: "0.25")}
                    >
                      <rect
                        x={svc.pos_x - 70}
                        y={svc.pos_y - 32}
                        width="140"
                        height="64"
                        rx="8"
                        fill={if(is_selected, do: "#1E2738", else: "#111722")}
                        stroke={if(is_selected, do: "#00F0FF", else: color)}
                        stroke-width={if(is_selected, do: "2.5", else: "1.5")}
                        filter={if(is_selected, do: "url(#topo-glow)", else: "none")}
                      />
                      <circle cx={svc.pos_x + 56} cy={svc.pos_y - 20} r="4" fill={color} />
                      <text x={svc.pos_x - 64} y={svc.pos_y - 17} fill="#94A3B8" font-size="8">
                        {String.upcase(svc.category)}
                      </text>
                      <text
                        x={svc.pos_x - 64}
                        y={svc.pos_y + 2}
                        fill="#F1F5F9"
                        font-size="11"
                        font-weight="bold"
                      >
                        {svc.name}
                      </text>
                      <text x={svc.pos_x - 64} y={svc.pos_y + 20} fill="#94A3B8" font-size="9">
                        {svc.latency_ms}ms · {round(svc.cpu_pct)}% cpu · {round(svc.error_rate * 100)}% err
                      </text>
                    </g>
                  <% end %>
                </svg>
              </div>
            </div>
          </div>

          <%!-- Side Inspector Panel --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-2xl flex flex-col justify-between">
            <%= if @selected_slug do %>
              <% svc = Map.get(@sim_state.services, @selected_slug) %>
              <%= if svc do %>
                <div class="space-y-4 text-xs">
                  <div class="pb-3 border-b border-[#263244]">
                    <div class="flex items-center justify-between">
                      <span class="text-[10px] font-bold uppercase tracking-wider text-cyan-400">Node Inspector</span>
                      <span class={[
                        "px-2 py-0.5 rounded text-[10px] uppercase font-bold",
                        svc.status == "healthy" &&
                          "bg-emerald-950 text-emerald-400 border border-emerald-500/30",
                        svc.status == "degraded" &&
                          "bg-amber-950 text-amber-400 border border-amber-500/30",
                        svc.status in ["failing", "offline"] &&
                          "bg-rose-950 text-rose-400 border border-rose-500/30"
                      ]}>
                        {svc.status}
                      </span>
                    </div>
                    <h3 class="text-base font-bold text-white mt-1">{svc.name}</h3>
                    <p class="text-slate-400 text-[11px] mt-0.5">
                      {Map.get(svc.metadata, "description", "")}
                    </p>
                  </div>

                  <%!-- Ingress / Egress connections --%>
                  <div>
                    <h4 class="font-bold text-slate-300 mb-1">Upstream Callers (Ingress):</h4>
                    <% callers = Enum.filter(@sim_state.dependencies, &(&1.target == svc.slug)) %>
                    <%= if callers == [] do %>
                      <p class="text-slate-500 text-[11px]">Top-level ingress edge.</p>
                    <% else %>
                      <div class="space-y-1">
                        <%= for dep <- callers do %>
                          <div class="p-1.5 rounded bg-[#161E2C] border border-[#263244] flex items-center justify-between">
                            <span class="font-mono text-cyan-400">{dep.source}</span>
                            <span class="text-slate-400">{dep.protocol}</span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <div>
                    <h4 class="font-bold text-slate-300 mb-1">Downstream Callees (Egress):</h4>
                    <% callees = Enum.filter(@sim_state.dependencies, &(&1.source == svc.slug)) %>
                    <%= if callees == [] do %>
                      <p class="text-slate-500 text-[11px]">Terminal store/worker.</p>
                    <% else %>
                      <div class="space-y-1">
                        <%= for dep <- callees do %>
                          <div class="p-1.5 rounded bg-[#161E2C] border border-[#263244] flex items-center justify-between">
                            <span class="font-mono text-cyan-400">{dep.target}</span>
                            <span class="text-slate-400">{dep.protocol}</span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                  <%!-- Metrics comparison --%>
                  <div class="p-3 rounded bg-[#161E2C] border border-[#263244] space-y-1.5">
                    <div class="flex justify-between">
                      <span class="text-slate-400">Latency:</span>
                      <span class="text-white font-mono">{svc.latency_ms} ms (base: {svc.baseline_latency_ms} ms)</span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-slate-400">CPU Usage:</span>
                      <span class="text-cyan-300 font-mono">{Float.round(svc.cpu_pct, 1)}%</span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-slate-400">Memory Heap:</span>
                      <span class="text-amber-300 font-mono">{svc.memory_mb} MB</span>
                    </div>
                    <div class="flex justify-between">
                      <span class="text-slate-400">Error Rate:</span>
                      <span class="text-rose-400 font-mono">{Float.round(svc.error_rate * 100, 2)}%</span>
                    </div>
                  </div>
                </div>

                <div class="pt-4 border-t border-[#263244]">
                  <.link
                    navigate={~p"/faults?target=#{svc.slug}"}
                    class="block text-center w-full py-2 rounded bg-cyan-950 hover:bg-cyan-900 border border-cyan-500/40 text-cyan-300 font-semibold"
                  >
                    Open in Fault Lab &rarr;
                  </.link>
                </div>
              <% end %>
            <% else %>
              <div class="text-center py-16 text-slate-500 text-xs">
                <.icon name="hero-cursor-arrow-rays" class="w-8 h-8 mx-auto mb-2 opacity-50" />
                Select any service node on the topology to view live ingress, egress, and telemetry.
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
