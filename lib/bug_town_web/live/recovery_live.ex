defmodule BugTownWeb.RecoveryLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper
  alias BugTown.Engine.Coordinator

  @recovery_strategies [
    {"restart", "Restart Service",
     "Gracefully cycle service process, resetting memory heap and connection pool",
     "hero-arrow-path"},
    {"restart_dependents", "Restart Service & Dependents",
     "Coordinated restart of target service along with all downstream queue consumers",
     "hero-arrow-path-rounded-square"},
    {"circuit_breaker", "Enable Circuit Breaker",
     "Trip breaker to open/half-open upon error threshold, isolating cascading timeouts",
     "hero-shield-exclamation"},
    {"adjust_timeout", "Calibrate Timeouts",
     "Tighten client call deadlines to prevent worker thread starvation", "hero-clock"},
    {"bounded_retries", "Bounded Retries & Backoff",
     "Enable exponential backoff with jitter to suppress retry amplification storms",
     "hero-arrow-path"},
    {"rate_limiting", "Request Rate Limiting",
     "Enforce token bucket rate limiting on ingress to shed excess load", "hero-funnel"},
    {"cache_fallback", "Redis Cache Fallback",
     "Serve stale cached data to preserve read availability during downstream database failures",
     "hero-circle-stack"},
    {"bulkhead", "Bulkhead Concurrency Limit",
     "Isolate thread pools so a degradation in checkout cannot starve user login",
     "hero-squares-2x2"},
    {"pool_adjustment", "DB Pool Expansion",
     "Enlarge max connection pool size and recycle deadlocked connections", "hero-server"},
    {"race_mitigation", "Concurrency Locking / Mutex",
     "Enforce serialized distributed locks on state transitions to prevent race collisions",
     "hero-lock-closed"},
    {"remove_fault", "Revoke Active Fault",
     "Explicitly remove active chaos faults from the target service", "hero-x-circle"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveHelper.setup_sim(:recovery, "Recovery Center · BugTown")
      |> assign(:strategies, @recovery_strategies)
      |> assign(:selected_strategy, "restart")
      |> assign(:target_service, "user-service")
      |> assign(:recovery_history, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("select_strategy", %{"strategy" => st}, socket) do
    {:noreply, assign(socket, :selected_strategy, st)}
  end

  @impl true
  def handle_event("target_change", %{"target" => target}, socket) do
    {:noreply, assign(socket, :target_service, target)}
  end

  @impl true
  def handle_event("execute_recovery", _params, socket) do
    strategy = socket.assigns.selected_strategy
    target = socket.assigns.target_service

    case Coordinator.apply_recovery(strategy, target) do
      {:ok, recovery} ->
        history = [recovery | socket.assigns.recovery_history] |> Enum.take(20)

        {:noreply,
         socket
         |> assign(:recovery_history, history)
         |> put_flash(:info, "Executed #{strategy} on #{target}: #{recovery.details}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Recovery failed: #{inspect(reason)}")}
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
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-[#263244]">
          <div>
            <h1 class="text-xl font-bold text-white flex items-center gap-2">
              <.icon name="hero-shield-check" class="w-5 h-5 text-emerald-400" />
              <span>RECOVERY CENTER & RESILIENCE MITIGATIONS</span>
            </h1>
            <p class="text-xs text-slate-400 mt-1">
              Apply verified operational remediations, deploy architectural shields, and measure time-to-recovery
            </p>
          </div>

          <div class="flex items-center gap-2">
            <.link
              navigate={~p"/faults"}
              class="px-3 py-1.5 rounded bg-[#161E2C] hover:bg-[#202B3D] border border-[#263244] text-slate-300 text-xs font-semibold cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-fire" class="w-3.5 h-3.5 text-rose-400" />
              <span>Fault Lab</span>
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Mitigation Strategy Selector & Launcher (2 cols) --%>
          <div class="lg:col-span-2 rounded-xl bg-[#111722] border border-[#263244] p-6 shadow-xl space-y-6">
            <div>
              <label class="block text-xs font-bold uppercase tracking-wider text-slate-300 mb-2">
                1. Select Resilience Recovery Strategy
              </label>

              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <%= for {strat_id, name, desc, icon} <- @strategies do %>
                  <button
                    type="button"
                    phx-click="select_strategy"
                    phx-value-strategy={strat_id}
                    class={[
                      "p-3.5 rounded-lg border text-left transition cursor-pointer flex flex-col justify-between",
                      @selected_strategy == strat_id &&
                        "bg-emerald-950/40 border-emerald-500/60 shadow-[0_0_12px_rgba(16,185,129,0.2)]",
                      @selected_strategy != strat_id &&
                        "bg-[#161E2C] border-[#263244] hover:border-slate-500 text-slate-400"
                    ]}
                  >
                    <div class="flex items-center gap-2 mb-1.5">
                      <.icon
                        name={icon}
                        class={[
                          "w-4 h-4",
                          @selected_strategy == strat_id && "text-emerald-400",
                          @selected_strategy != strat_id && "text-slate-400"
                        ]}
                      />
                      <span class={[
                        "text-xs font-bold",
                        @selected_strategy == strat_id && "text-white",
                        @selected_strategy != strat_id && "text-slate-200"
                      ]}>
                        {name}
                      </span>
                    </div>
                    <span class="text-[11px] text-slate-400 leading-relaxed">{desc}</span>
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Target selection and execution button --%>
            <div class="p-4 rounded-lg bg-[#0C101A] border border-[#263244] flex flex-col sm:flex-row items-center gap-4">
              <div class="w-full sm:w-1/2">
                <label class="block text-xs font-bold text-slate-300 mb-1">Target Service</label>
                <select
                  phx-change="target_change"
                  name="target"
                  class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-xs text-white font-mono focus:border-cyan-400 focus:outline-none"
                >
                  <%= for {slug, svc} <- @sim_state.services do %>
                    <option value={slug} selected={@target_service == slug}>
                      {svc.name} ({slug})
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="w-full sm:w-1/2 flex items-end">
                <button
                  type="button"
                  phx-click="execute_recovery"
                  class="w-full py-2.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs uppercase tracking-wider transition cursor-pointer shadow-lg shadow-emerald-950/50 flex items-center justify-center gap-2"
                >
                  <.icon name="hero-bolt" class="w-4 h-4" />
                  <span>Deploy Recovery Mitigation</span>
                </button>
              </div>
            </div>
          </div>

          <%!-- Active Recovery Shields & Telemetry Effects (Right Column) --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl flex flex-col justify-between">
            <div>
              <div class="flex items-center justify-between pb-3 border-b border-[#263244]">
                <h3 class="text-xs font-bold uppercase tracking-wider text-slate-200 flex items-center gap-2">
                  <.icon name="hero-shield-check" class="w-4 h-4 text-emerald-400" />
                  Active Shield Registry
                </h3>
                <span class="px-2 py-0.5 rounded text-[10px] font-mono bg-[#161E2C] text-emerald-400 border border-emerald-500/30">
                  {map_size(@sim_state.active_recoveries)} Active
                </span>
              </div>

              <div class="mt-4 space-y-3 max-h-[500px] overflow-y-auto text-xs">
                <%= if map_size(@sim_state.active_recoveries) == 0 do %>
                  <div class="text-center py-16 text-slate-500 text-xs">
                    <.icon
                      name="hero-shield-exclamation"
                      class="w-8 h-8 mx-auto mb-2 opacity-40 text-slate-500"
                    /> No active recovery shields deployed. Baseline policies active.
                  </div>
                <% else %>
                  <%= for {id, rec} <- @sim_state.active_recoveries do %>
                    <div class="p-3 rounded-lg bg-[#161E2C] border border-emerald-500/40 space-y-2">
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-white font-mono">{id}</span>
                        <span class="px-1.5 py-0.2 rounded text-[10px] uppercase font-bold bg-emerald-950 text-emerald-300 border border-emerald-500/30">
                          {rec.status}
                        </span>
                      </div>

                      <div class="text-slate-200 font-semibold">
                        {String.replace(rec.type, "_", " ") |> String.capitalize()}
                      </div>

                      <div class="text-[11px] text-slate-400">
                        Target: <span class="text-cyan-400 font-mono">{rec.target}</span>
                      </div>

                      <p class="text-[11px] text-slate-300 bg-[#0C101A] p-2 rounded border border-[#263244]">
                        {rec.details}
                      </p>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <%!-- Recovery Outcomes & Audit Log --%>
        <div class="rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-xl">
          <div class="px-5 py-3 border-b border-[#263244] bg-[#161E2C]/50 text-xs font-bold text-slate-200 uppercase tracking-wider">
            Remediation Audit Trail & Verified Impact
          </div>

          <div class="divide-y divide-[#263244] text-xs">
            <%= if @recovery_history == [] do %>
              <div class="p-8 text-center text-slate-500">
                Executed recoveries will record their before/after telemetry verification here.
              </div>
            <% else %>
              <%= for rec <- @recovery_history do %>
                <div class="p-4 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                  <div class="space-y-1">
                    <div class="flex items-center gap-2">
                      <span class="font-bold text-white font-mono">{rec.id}</span>
                      <span class="text-cyan-300 font-bold uppercase">{rec.type}</span>
                      <span class="text-slate-400">on
                      <strong class="text-white font-mono">{rec.target}</strong></span>
                    </div>
                    <p class="text-slate-300">{rec.details}</p>
                  </div>

                  <div class="flex items-center gap-4 text-[11px] font-mono text-slate-400 shrink-0">
                    <div>
                      Before Err:
                      <span class="text-rose-400">{Float.round(rec.metrics_before.error_rate * 100, 2)}%</span>
                    </div>
                    <div class="text-emerald-400 font-bold flex items-center gap-1">
                      <.icon name="hero-check-circle" class="w-4 h-4" /> Verified Effective
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
