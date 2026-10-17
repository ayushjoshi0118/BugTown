defmodule BugTownWeb.SettingsLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper
  alias BugTown.Engine.Coordinator

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveHelper.setup_sim(:settings, "Settings · BugTown")
      |> assign(:seed_input, 42)
      |> assign(:error_threshold, 15)
      |> assign(:latency_threshold, 250)
      |> assign(:memory_threshold, 750)

    {:ok, socket}
  end

  @impl true
  def handle_event("speed_change", %{"speed" => speed_str}, socket) do
    case Float.parse(speed_str) do
      {speed, _} when speed > 0 ->
        {:ok, state} = Coordinator.set_speed(speed)

        {:noreply,
         assign(socket, :sim_state, state)
         |> put_flash(:info, "Simulation speed adjusted to #{speed}x.")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_thresholds", params, socket) do
    err = params["error_threshold"]
    lat = params["latency_threshold"]
    mem = params["memory_threshold"]

    socket =
      socket
      |> assign(:error_threshold, err)
      |> assign(:latency_threshold, lat)
      |> assign(:memory_threshold, mem)
      |> put_flash(:info, "Operational alert thresholds updated.")

    {:noreply, socket}
  end

  @impl true
  def handle_event("hard_reset", _params, socket) do
    {:ok, state} = Coordinator.reset_sim()

    {:noreply,
     socket
     |> assign(:sim_state, state)
     |> put_flash(:info, "Complete cluster state purged and reset to pristine baseline.")}
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
      <div class="p-6 space-y-6 max-w-[1200px] mx-auto w-full text-xs">
        <%!-- Header --%>
        <div class="pb-4 border-b border-[#263244]">
          <h1 class="text-xl font-bold text-white flex items-center gap-2">
            <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-cyan-400" />
            <span>SIMULATOR CONFIGURATION & ENGINE THRESHOLDS</span>
          </h1>
          <p class="text-xs text-slate-400 mt-1">
            Fine-tune simulation clock rate, alert triggers, deterministic seeds, and cluster runtime parameters
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <%!-- Clock & Speed Card --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-4">
            <h3 class="font-bold uppercase tracking-wider text-white flex items-center gap-2 text-xs">
              <.icon name="hero-clock" class="w-4 h-4 text-cyan-400" /> Engine Clock & Execution Speed
            </h3>

            <div class="space-y-3">
              <div>
                <label class="block text-slate-400 mb-1">Simulation Speed Multiplier</label>
                <div class="grid grid-cols-4 gap-2">
                  <%= for spd <- [0.5, 1.0, 2.0, 5.0] do %>
                    <button
                      type="button"
                      phx-click="speed_change"
                      phx-value-speed={to_string(spd)}
                      class={[
                        "py-2 rounded font-mono font-bold border transition cursor-pointer text-center",
                        @sim_state.speed == spd &&
                          "bg-cyan-500/20 text-cyan-300 border-cyan-400 shadow-[0_0_10px_rgba(0,240,255,0.2)]",
                        @sim_state.speed != spd &&
                          "bg-[#161E2C] text-slate-400 border-[#263244] hover:border-slate-500"
                      ]}
                    >
                      {spd}x
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="p-3 rounded bg-[#0C101A] border border-[#263244] text-[11px] text-slate-400 space-y-1">
                <div>Base tick duration: <strong class="text-white font-mono">800 ms</strong></div>
                <div>
                  Current effective interval:
                  <strong class="text-cyan-400 font-mono">{round(800 / max(0.1, @sim_state.speed))} ms</strong>
                </div>
                <div>
                  Elapsed simulated time:
                  <strong class="text-white font-mono">{@sim_state.sim_time_seconds} seconds</strong>
                  (Ticks: {@sim_state.tick_count})
                </div>
              </div>
            </div>
          </div>

          <%!-- Alert Thresholds Card --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-4">
            <h3 class="font-bold uppercase tracking-wider text-white flex items-center gap-2 text-xs">
              <.icon name="hero-bell-alert" class="w-4 h-4 text-amber-400" />
              Incident Trigger Thresholds
            </h3>

            <form phx-submit="save_thresholds" class="space-y-3">
              <div>
                <label class="block text-slate-400 mb-1">Critical Error Rate SLO (%): {@error_threshold}%</label>
                <input
                  type="range"
                  name="error_threshold"
                  min="5"
                  max="40"
                  value={@error_threshold}
                  class="w-full accent-rose-500"
                />
              </div>

              <div>
                <label class="block text-slate-400 mb-1">Latency SLA Threshold (ms): {@latency_threshold} ms</label>
                <input
                  type="range"
                  name="latency_threshold"
                  min="100"
                  max="800"
                  step="50"
                  value={@latency_threshold}
                  class="w-full accent-cyan-500"
                />
              </div>

              <div>
                <label class="block text-slate-400 mb-1">Memory Alert Threshold (MB): {@memory_threshold} MB</label>
                <input
                  type="range"
                  name="memory_threshold"
                  min="400"
                  max="1200"
                  step="50"
                  value={@memory_threshold}
                  class="w-full accent-amber-500"
                />
              </div>

              <button
                type="submit"
                class="w-full py-2 rounded bg-[#161E2C] hover:bg-[#202B3D] text-slate-200 border border-[#263244] font-semibold cursor-pointer"
              >
                Save Threshold Parameters
              </button>
            </form>
          </div>
        </div>

        <%!-- Destructive / Reset Section --%>
        <div class="rounded-xl bg-[#111722] border border-rose-500/30 p-5 shadow-xl space-y-3">
          <h3 class="font-bold uppercase tracking-wider text-rose-400 flex items-center gap-2 text-xs">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-rose-400" />
            Danger Zone & Cluster Reset
          </h3>
          <p class="text-slate-400 text-xs">
            Restores the distributed topology to pristine baseline. Revokes all active chaos injections,
            purges living bugs, and recalculates nominal steady-state telemetry.
          </p>

          <button
            type="button"
            phx-click="hard_reset"
            data-confirm="Are you sure you want to completely purge active faults and reset the cluster?"
            class="px-4 py-2 rounded bg-rose-950/80 hover:bg-rose-900 border border-rose-500/50 text-rose-300 font-bold uppercase tracking-wider cursor-pointer transition shadow"
          >
            Hard Reset Entire Simulation Cluster
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
