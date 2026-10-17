defmodule BugTownWeb.FaultLabLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper
  alias BugTown.Engine.Coordinator

  @impl true
  def mount(params, _session, socket) do
    target = params["target"] || "user-service"

    socket =
      socket
      |> LiveHelper.setup_sim(:faults, "Fault Injection Lab · BugTown")
      |> assign(:selected_fault_type, "memory_leak")
      |> assign(:target_service, target)
      |> assign(:severity, "high")
      |> assign(:duration_ticks, 60)
      # Memory leak params
      |> assign(:growth_rate_mb, 40)
      |> assign(:max_memory_mb, 850)
      # Race condition params
      |> assign(:concurrency_intensity, 0.75)
      |> assign(:conflict_probability, 0.50)
      # Service crash params
      |> assign(:crash_mode, "sigkill")
      |> assign(:auto_restart, false)
      |> assign(:restart_after_ticks, 20)
      # Network latency params
      |> assign(:added_latency_ms, 400)
      |> assign(:jitter_ms, 50)
      # Packet loss params
      |> assign(:loss_probability, 0.35)
      # Database failure params
      |> assign(:db_mode, "connection_failure")

    {:ok, socket}
  end

  @impl true
  def handle_event("select_fault_type", %{"type" => type}, socket) do
    # Auto-adjust default target for DB failure
    target = if type == "database_failure", do: "postgres-db", else: socket.assigns.target_service
    {:noreply, socket |> assign(:selected_fault_type, type) |> assign(:target_service, target)}
  end

  @impl true
  def handle_event("form_change", params, socket) do
    # Update assigns based on incoming form input
    socket =
      socket
      |> maybe_assign(:target_service, params["target_service"])
      |> maybe_assign(:severity, params["severity"])
      |> maybe_assign_int(:duration_ticks, params["duration_ticks"])
      |> maybe_assign_int(:growth_rate_mb, params["growth_rate_mb"])
      |> maybe_assign_int(:max_memory_mb, params["max_memory_mb"])
      |> maybe_assign_float(:concurrency_intensity, params["concurrency_intensity"])
      |> maybe_assign_float(:conflict_probability, params["conflict_probability"])
      |> maybe_assign(:crash_mode, params["crash_mode"])
      |> maybe_assign_bool(:auto_restart, params["auto_restart"])
      |> maybe_assign_int(:restart_after_ticks, params["restart_after_ticks"])
      |> maybe_assign_int(:added_latency_ms, params["added_latency_ms"])
      |> maybe_assign_int(:jitter_ms, params["jitter_ms"])
      |> maybe_assign_float(:loss_probability, params["loss_probability"])
      |> maybe_assign(:db_mode, params["db_mode"])

    {:noreply, socket}
  end

  @impl true
  def handle_event("inject_fault", params, socket) do
    type = socket.assigns.selected_fault_type
    target = params["target_service"] || socket.assigns.target_service
    severity = params["severity"] || socket.assigns.severity

    duration =
      case Integer.parse(to_string(params["duration_ticks"] || socket.assigns.duration_ticks)) do
        {d, _} -> d
        _ -> socket.assigns.duration_ticks
      end

    fault_params =
      case type do
        "memory_leak" ->
          %{
            "growth_rate_mb" => socket.assigns.growth_rate_mb,
            "max_memory_mb" => socket.assigns.max_memory_mb,
            "duration_ticks" => duration
          }

        "race_condition" ->
          %{
            "concurrency_intensity" => socket.assigns.concurrency_intensity,
            "conflict_probability" => socket.assigns.conflict_probability,
            "duration_ticks" => duration
          }

        "service_crash" ->
          %{
            "crash_mode" => socket.assigns.crash_mode,
            "auto_restart" => socket.assigns.auto_restart,
            "restart_after_ticks" => socket.assigns.restart_after_ticks,
            "duration_ticks" => duration
          }

        "network_latency" ->
          %{
            "added_latency_ms" => socket.assigns.added_latency_ms,
            "jitter_ms" => socket.assigns.jitter_ms,
            "duration_ticks" => duration
          }

        "packet_loss" ->
          %{
            "loss_probability" => socket.assigns.loss_probability,
            "duration_ticks" => duration
          }

        "database_failure" ->
          %{
            "mode" => socket.assigns.db_mode,
            "duration_ticks" => duration
          }

        _ ->
          %{}
      end

    {:ok, fault} = Coordinator.inject_fault(type, target, fault_params, severity, duration)

    {:noreply,
     socket
     |> put_flash(:info, "Fault #{fault.id} successfully injected into #{target}!")}
  end

  @impl true
  def handle_event("remove_fault", %{"id" => fault_id}, socket) do
    case Coordinator.remove_fault(fault_id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Fault #{fault_id} revoked and removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Fault not found.")}
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

  defp maybe_assign(socket, _key, nil), do: socket
  defp maybe_assign(socket, key, val), do: assign(socket, key, val)

  defp maybe_assign_int(socket, _key, nil), do: socket

  defp maybe_assign_int(socket, key, val) do
    case Integer.parse(to_string(val)) do
      {int, _} -> assign(socket, key, int)
      _ -> socket
    end
  end

  defp maybe_assign_float(socket, _key, nil), do: socket

  defp maybe_assign_float(socket, key, val) do
    case Float.parse(to_string(val)) do
      {flt, _} -> assign(socket, key, flt)
      _ -> socket
    end
  end

  defp maybe_assign_bool(socket, key, val), do: assign(socket, key, val == "true" or val == true)

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
        <div class="pb-4 border-b border-[#263244]">
          <h1 class="text-xl font-bold text-white flex items-center gap-2">
            <.icon name="hero-fire" class="w-5 h-5 text-rose-500" />
            <span>FAULT INJECTION LAB</span>
          </h1>
          <p class="text-xs text-slate-400 mt-1">
            Simulate realistic distributed failure modes, resource saturation, and network anomalies
          </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Fault Configuration Form (Left 2 columns) --%>
          <div class="lg:col-span-2 rounded-xl bg-[#111722] border border-[#263244] p-6 shadow-xl space-y-6">
            <div>
              <label class="block text-xs font-bold uppercase tracking-wider text-slate-300 mb-2">
                1. Select Chaos Fault Vector
              </label>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
                <% fault_types = [
                  {"memory_leak", "Memory Leak", "Heap saturation & GC pause",
                   "hero-arrow-trending-up"},
                  {"race_condition", "Race Condition", "Concurrent state collision",
                   "hero-arrows-pointing-in"},
                  {"service_crash", "Service Crash", "Process panic / SIGKILL", "hero-bolt-slash"},
                  {"network_latency", "Network Latency", "Added RTT delay & jitter", "hero-clock"},
                  {"packet_loss", "Packet Loss", "Dropped ingress/egress packets", "hero-scissors"},
                  {"database_failure", "Database Outage", "Pool exhaustion & lock timeouts",
                   "hero-server-stack"}
                ] %>
                <%= for {type_id, name, desc, icon} <- fault_types do %>
                  <button
                    type="button"
                    phx-click="select_fault_type"
                    phx-value-type={type_id}
                    class={[
                      "p-3 rounded-lg border text-left transition cursor-pointer flex flex-col justify-between",
                      @selected_fault_type == type_id &&
                        "bg-rose-950/40 border-rose-500/60 shadow-[0_0_12px_rgba(244,63,94,0.15)]",
                      @selected_fault_type != type_id &&
                        "bg-[#161E2C] border-[#263244] hover:border-slate-500 text-slate-400"
                    ]}
                  >
                    <div class="flex items-center gap-2 mb-1">
                      <.icon
                        name={icon}
                        class={[
                          "w-4 h-4",
                          @selected_fault_type == type_id && "text-rose-400",
                          @selected_fault_type != type_id && "text-slate-400"
                        ]}
                      />
                      <span class={[
                        "text-xs font-bold",
                        @selected_fault_type == type_id && "text-white",
                        @selected_fault_type != type_id && "text-slate-200"
                      ]}>
                        {name}
                      </span>
                    </div>
                    <span class="text-[10px] text-slate-400 leading-tight">{desc}</span>
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Target & Severity Row --%>
            <form
              id="fault-injection-form"
              phx-change="form_change"
              phx-submit="inject_fault"
              class="space-y-6"
            >
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div>
                  <label class="block text-xs font-bold text-slate-300 mb-1">Target Service</label>
                  <select
                    name="target_service"
                    class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-xs text-white font-mono focus:border-cyan-400 focus:outline-none"
                  >
                    <%= for {slug, svc} <- @sim_state.services do %>
                      <option value={slug} selected={@target_service == slug}>
                        {svc.name} ({slug})
                      </option>
                    <% end %>
                  </select>
                </div>

                <div>
                  <label class="block text-xs font-bold text-slate-300 mb-1">Severity Rating</label>
                  <select
                    name="severity"
                    class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-xs text-white font-mono focus:border-cyan-400 focus:outline-none"
                  >
                    <option value="low" selected={@severity == "low"}>
                      Low (Noticeable degradation)
                    </option>
                    <option value="medium" selected={@severity == "medium"}>
                      Medium (SLO breach risk)
                    </option>
                    <option value="high" selected={@severity == "high"}>
                      High (Service Degraded)
                    </option>
                    <option value="critical" selected={@severity == "critical"}>
                      Critical (Severe Outage)
                    </option>
                  </select>
                </div>

                <div>
                  <label class="block text-xs font-bold text-slate-300 mb-1">Duration (Ticks / Sec)</label>
                  <input
                    type="number"
                    name="duration_ticks"
                    value={@duration_ticks}
                    min="10"
                    max="300"
                    class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-xs text-white font-mono focus:border-cyan-400 focus:outline-none"
                  />
                </div>
              </div>

              <%!-- Dynamic Parameter Sub-panel based on chosen fault type --%>
              <div class="p-4 rounded-lg bg-[#0C101A] border border-[#263244] space-y-4">
                <span class="text-xs font-bold uppercase tracking-wider text-cyan-400">
                  {String.replace(@selected_fault_type, "_", " ")} Parameters
                </span>

                <%= case @selected_fault_type do %>
                  <% "memory_leak" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
                      <div>
                        <label class="block text-slate-300 mb-1">Growth Rate: {@growth_rate_mb} MB/tick</label>
                        <input
                          type="range"
                          name="growth_rate_mb"
                          min="10"
                          max="100"
                          value={@growth_rate_mb}
                          class="w-full accent-rose-500"
                        />
                      </div>
                      <div>
                        <label class="block text-slate-300 mb-1">Max OOM Threshold: {@max_memory_mb} MB</label>
                        <input
                          type="range"
                          name="max_memory_mb"
                          min="500"
                          max="1500"
                          step="50"
                          value={@max_memory_mb}
                          class="w-full accent-rose-500"
                        />
                      </div>
                    </div>
                  <% "race_condition" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
                      <div>
                        <label class="block text-slate-300 mb-1">Concurrency Intensity: {round(
                          @concurrency_intensity * 100
                        )}%</label>
                        <input
                          type="range"
                          name="concurrency_intensity"
                          min="0.1"
                          max="1.0"
                          step="0.05"
                          value={@concurrency_intensity}
                          class="w-full accent-amber-500"
                        />
                      </div>
                      <div>
                        <label class="block text-slate-300 mb-1">Conflict Collision Prob: {round(
                          @conflict_probability * 100
                        )}%</label>
                        <input
                          type="range"
                          name="conflict_probability"
                          min="0.1"
                          max="1.0"
                          step="0.05"
                          value={@conflict_probability}
                          class="w-full accent-amber-500"
                        />
                      </div>
                    </div>
                  <% "service_crash" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
                      <div>
                        <label class="block text-slate-300 mb-1">Crash Termination Mode</label>
                        <select
                          name="crash_mode"
                          class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white"
                        >
                          <option value="sigkill" selected={@crash_mode == "sigkill"}>
                            SIGKILL (Immediate Process Death)
                          </option>
                          <option value="panic" selected={@crash_mode == "panic"}>
                            Panic / Uncaught Exception
                          </option>
                          <option value="freeze" selected={@crash_mode == "freeze"}>
                            Thread Lock / Complete Freeze
                          </option>
                        </select>
                      </div>
                      <div>
                        <label class="block text-slate-300 mb-1">Supervisor Auto-Restart Policy</label>
                        <select
                          name="auto_restart"
                          class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white"
                        >
                          <option value="false" selected={not @auto_restart}>
                            Manual Recovery Only
                          </option>
                          <option value="true" selected={@auto_restart}>
                            Auto-Restart After 15 Ticks
                          </option>
                        </select>
                      </div>
                    </div>
                  <% "network_latency" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
                      <div>
                        <label class="block text-slate-300 mb-1">Added Delay: {@added_latency_ms} ms</label>
                        <input
                          type="range"
                          name="added_latency_ms"
                          min="50"
                          max="1500"
                          step="25"
                          value={@added_latency_ms}
                          class="w-full accent-cyan-500"
                        />
                      </div>
                      <div>
                        <label class="block text-slate-300 mb-1">Jitter Variance: ±{@jitter_ms} ms</label>
                        <input
                          type="range"
                          name="jitter_ms"
                          min="0"
                          max="150"
                          step="10"
                          value={@jitter_ms}
                          class="w-full accent-cyan-500"
                        />
                      </div>
                    </div>
                  <% "packet_loss" -> %>
                    <div class="text-xs">
                      <label class="block text-slate-300 mb-1">Drop Probability: {round(
                        @loss_probability * 100
                      )}%</label>
                      <input
                        type="range"
                        name="loss_probability"
                        min="0.05"
                        max="0.80"
                        step="0.05"
                        value={@loss_probability}
                        class="w-full accent-rose-500"
                      />
                    </div>
                  <% "database_failure" -> %>
                    <div class="text-xs">
                      <label class="block text-slate-300 mb-1">Database Failure Mode</label>
                      <select
                        name="db_mode"
                        class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white"
                      >
                        <option value="connection_failure" selected={@db_mode == "connection_failure"}>
                          TCP Connection Refused (Port 5432 down)
                        </option>
                        <option value="pool_exhaustion" selected={@db_mode == "pool_exhaustion"}>
                          Connection Pool Starvation (100/100 connections busy)
                        </option>
                        <option value="slow_queries" selected={@db_mode == "slow_queries"}>
                          Table Scan Latency Spike (500ms+ per query)
                        </option>
                      </select>
                    </div>
                <% end %>
              </div>

              <button
                type="submit"
                class="w-full py-2.5 rounded-lg bg-rose-600 hover:bg-rose-500 text-white font-bold text-xs uppercase tracking-wider transition cursor-pointer shadow-lg shadow-rose-950/50 flex items-center justify-center gap-2"
              >
                <.icon name="hero-bolt" class="w-4 h-4" />
                <span>Inject Fault Into Runtime</span>
              </button>
            </form>
          </div>

          <%!-- Active Injected Faults List (Right Column) --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl flex flex-col justify-between">
            <div>
              <div class="flex items-center justify-between pb-3 border-b border-[#263244]">
                <h3 class="text-xs font-bold uppercase tracking-wider text-slate-200 flex items-center gap-2">
                  <.icon name="hero-fire" class="w-4 h-4 text-rose-400" /> Active Fault Registry
                </h3>
                <span class="px-2 py-0.5 rounded text-[10px] font-mono bg-[#161E2C] text-rose-400 border border-rose-500/30">
                  {map_size(@sim_state.active_faults)} Active
                </span>
              </div>

              <div class="mt-4 space-y-3 max-h-[500px] overflow-y-auto text-xs">
                <%= if map_size(@sim_state.active_faults) == 0 do %>
                  <div class="text-center py-16 text-slate-500 text-xs">
                    <.icon
                      name="hero-shield-check"
                      class="w-8 h-8 mx-auto mb-2 opacity-40 text-emerald-400"
                    /> No active faults injected. System operating in nominal baseline envelope.
                  </div>
                <% else %>
                  <%= for {id, fault} <- @sim_state.active_faults do %>
                    <div class="p-3 rounded-lg bg-[#161E2C] border border-rose-500/40 space-y-2">
                      <div class="flex items-center justify-between">
                        <span class="font-bold text-white font-mono">{fault.id}</span>
                        <span class="px-1.5 py-0.2 rounded text-[10px] uppercase font-bold bg-rose-950 text-rose-300 border border-rose-500/30">
                          {fault.severity}
                        </span>
                      </div>

                      <div class="text-slate-300 font-medium">
                        {String.replace(fault.type, "_", " ") |> String.capitalize()}
                      </div>

                      <div class="text-[11px] text-slate-400">
                        Target: <span class="text-cyan-400 font-mono">{fault.target}</span>
                      </div>

                      <div class="text-[10px] text-slate-500 flex justify-between">
                        <span>Active since: T+{fault.injected_at_tick}</span>
                        <span>Duration: {fault.duration_ticks} ticks</span>
                      </div>

                      <button
                        phx-click="remove_fault"
                        phx-value-id={id}
                        class="w-full mt-2 py-1.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold border border-slate-600 transition cursor-pointer"
                      >
                        Revoke / Remove Fault
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
