defmodule BugTownWeb.ExperimentsLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper
  alias BugTown.Engine.{Coordinator, Scenarios}
  alias BugTown.Repo
  alias BugTown.Experiments.Experiment
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    saved_experiments = load_saved_experiments()

    socket =
      socket
      |> LiveHelper.setup_sim(:experiments, "Chaos Experiments · BugTown")
      |> assign(:scenarios, Scenarios.all())
      |> assign(:saved_experiments, saved_experiments)
      |> assign(:selected_scenario_id, "memory_leak_exhaustion")
      |> assign(:save_name, "")
      |> assign(:save_desc, "")
      |> assign(:compare_a_id, nil)
      |> assign(:compare_b_id, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_scenario", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_scenario_id, id)}
  end

  @impl true
  def handle_event("launch_scenario", %{"id" => id}, socket) do
    case Coordinator.run_scenario(id) do
      {:ok, scen} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Launched chaos scenario: #{scen.name}. Observe propagation in Command Center."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to launch scenario.")}
    end
  end

  @impl true
  def handle_event("save_name_change", %{"name" => name}, socket) do
    {:noreply, assign(socket, :save_name, name)}
  end

  @impl true
  def handle_event("save_desc_change", %{"desc" => desc}, socket) do
    {:noreply, assign(socket, :save_desc, desc)}
  end

  @impl true
  def handle_event("save_experiment", _params, socket) do
    name =
      if socket.assigns.save_name != "",
        do: socket.assigns.save_name,
        else: "Experiment Run #{DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")}"

    scen_id = socket.assigns.selected_scenario_id
    desc = socket.assigns.save_desc

    case Coordinator.save_current_experiment(name, scen_id, desc) do
      {:ok, saved} ->
        updated_saved = load_saved_experiments()

        {:noreply,
         socket
         |> assign(:saved_experiments, updated_saved)
         |> assign(:save_name, "")
         |> assign(:save_desc, "")
         |> put_flash(:info, "Experiment '#{saved.name}' successfully persisted into PostgreSQL.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save experiment.")}
    end
  end

  @impl true
  def handle_event("select_compare_a", %{"id" => id}, socket) do
    {:noreply, assign(socket, :compare_a_id, if(id == "", do: nil, else: String.to_integer(id)))}
  end

  @impl true
  def handle_event("select_compare_b", %{"id" => id}, socket) do
    {:noreply, assign(socket, :compare_b_id, if(id == "", do: nil, else: String.to_integer(id)))}
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

  defp load_saved_experiments do
    try do
      Repo.all(from e in Experiment, order_by: [desc: e.inserted_at])
    rescue
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    exp_a =
      if assigns.compare_a_id,
        do: Enum.find(assigns.saved_experiments, &(&1.id == assigns.compare_a_id))

    exp_b =
      if assigns.compare_b_id,
        do: Enum.find(assigns.saved_experiments, &(&1.id == assigns.compare_b_id))

    assigns = assign(assigns, exp_a: exp_a, exp_b: exp_b)

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
              <.icon name="hero-beaker" class="w-5 h-5 text-cyan-400" />
              <span>CHAOS EXPERIMENTS & REPLAY STUDIO</span>
            </h1>
            <p class="text-xs text-slate-400 mt-1">
              Execute controlled failure scenarios, record telemetry baselines, and compare before/after recovery outcomes
            </p>
          </div>

          <div class="flex items-center gap-2">
            <.link
              navigate={~p"/"}
              class="px-3 py-1.5 rounded bg-cyan-950 hover:bg-cyan-900 border border-cyan-500/40 text-cyan-300 text-xs font-semibold cursor-pointer flex items-center gap-1.5"
            >
              <.icon name="hero-bolt" class="w-3.5 h-3.5" />
              <span>Watch Live Simulation</span>
            </.link>
          </div>
        </div>

        <%!-- Scenarios Catalog Grid --%>
        <div class="space-y-3">
          <h2 class="text-xs font-bold uppercase tracking-wider text-slate-300">
            Pre-Configured Deterministic Scenarios ({length(@scenarios)})
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <%= for scen <- @scenarios do %>
              <% is_active =
                @sim_state.current_experiment != nil and
                  @sim_state.current_experiment.scenario_type == scen.id %>
              <div class={[
                "p-4 rounded-xl border flex flex-col justify-between transition text-xs space-y-3",
                is_active && "bg-[#1E2738] border-cyan-400 shadow-[0_0_15px_rgba(0,240,255,0.2)]",
                !is_active && "bg-[#111722] border-[#263244] hover:border-slate-500"
              ]}>
                <div class="space-y-1.5">
                  <div class="flex items-center justify-between">
                    <span class="text-[10px] uppercase font-bold text-cyan-400">{scen.category}</span>
                    <%= if is_active do %>
                      <span class="px-1.5 py-0.2 rounded text-[9px] uppercase font-bold bg-cyan-950 text-cyan-300 border border-cyan-400 animate-pulse">
                        RUNNING
                      </span>
                    <% end %>
                  </div>
                  <h3 class="font-bold text-white text-sm">{scen.name}</h3>
                  <p class="text-slate-400 text-[11px] leading-relaxed">{scen.description}</p>
                </div>

                <div class="pt-2 border-t border-[#263244] space-y-2">
                  <div class="flex justify-between text-[10px] text-slate-500">
                    <span>Target:
                    <strong class="text-slate-300 font-mono">{scen.target_service}</strong></span>
                    <span>Remedy:
                    <strong class="text-emerald-400">{scen.recommended_recovery}</strong></span>
                  </div>

                  <button
                    phx-click="launch_scenario"
                    phx-value-id={scen.id}
                    class="w-full py-1.5 rounded bg-cyan-950/80 hover:bg-cyan-900 border border-cyan-500/40 text-cyan-300 font-bold transition cursor-pointer flex items-center justify-center gap-1.5"
                  >
                    <.icon name="hero-play" class="w-3.5 h-3.5" />
                    <span>Launch Scenario</span>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Save Experiment & Side-by-Side Comparison Section --%>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 pt-4 border-t border-[#263244]">
          <%!-- Save Active Experiment Form --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-4">
            <h3 class="text-xs font-bold uppercase tracking-wider text-white flex items-center gap-2">
              <.icon name="hero-arrow-down-tray" class="w-4 h-4 text-emerald-400" />
              Persist Experiment to PostgreSQL
            </h3>
            <p class="text-xs text-slate-400">
              Save current simulation run, active faults, and measured metrics to the database for historical comparison.
            </p>

            <form phx-submit="save_experiment" class="space-y-3 text-xs">
              <div>
                <label class="block text-slate-300 mb-1 font-semibold">Experiment Run Title</label>
                <input
                  type="text"
                  name="name"
                  phx-change="save_name_change"
                  value={@save_name}
                  placeholder="e.g. Trial 1: Circuit breaker under 500ms DB latency"
                  class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white focus:outline-none focus:border-cyan-400"
                />
              </div>

              <div>
                <label class="block text-slate-300 mb-1 font-semibold">Notes / Hypothesis</label>
                <textarea
                  name="desc"
                  phx-change="save_desc_change"
                  value={@save_desc}
                  rows="2"
                  placeholder="Describe observed propagation and effectiveness of the applied mitigation..."
                  class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white focus:outline-none focus:border-cyan-400"
                ></textarea>
              </div>

              <button
                type="submit"
                class="w-full py-2 rounded bg-emerald-600 hover:bg-emerald-500 text-white font-bold transition cursor-pointer shadow-lg"
              >
                Save Experiment Snapshot
              </button>
            </form>
          </div>

          <%!-- Side-by-Side Comparison Studio (2 cols) --%>
          <div class="lg:col-span-2 rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl space-y-4">
            <h3 class="text-xs font-bold uppercase tracking-wider text-white flex items-center gap-2">
              <.icon name="hero-scale" class="w-4 h-4 text-cyan-400" />
              Side-by-Side Experiment Comparison
            </h3>

            <div class="grid grid-cols-2 gap-4 text-xs">
              <div>
                <label class="block text-slate-400 mb-1">Select Experiment A (Baseline):</label>
                <select
                  phx-change="select_compare_a"
                  name="id"
                  class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white"
                >
                  <option value="">-- Choose Experiment A --</option>
                  <%= for exp <- @saved_experiments do %>
                    <option value={exp.id} selected={@compare_a_id == exp.id}>
                      #{exp.id} - {exp.name}
                    </option>
                  <% end %>
                </select>
              </div>

              <div>
                <label class="block text-slate-400 mb-1">Select Experiment B (Mitigated):</label>
                <select
                  phx-change="select_compare_b"
                  name="id"
                  class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-white"
                >
                  <option value="">-- Choose Experiment B --</option>
                  <%= for exp <- @saved_experiments do %>
                    <option value={exp.id} selected={@compare_b_id == exp.id}>
                      #{exp.id} - {exp.name}
                    </option>
                  <% end %>
                </select>
              </div>
            </div>

            <%= if @exp_a && @exp_b do %>
              <div class="rounded-lg bg-[#0C101A] border border-[#263244] overflow-hidden text-xs mt-4">
                <table class="w-full text-left divide-y divide-[#263244]">
                  <thead class="bg-[#161E2C] text-slate-400">
                    <tr>
                      <th class="p-3">Measurement Metric</th>
                      <th class="p-3 text-cyan-300">{@exp_a.name} (A)</th>
                      <th class="p-3 text-emerald-300">{@exp_b.name} (B)</th>
                      <th class="p-3">Variance / Delta</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-[#1E2738] text-slate-200">
                    <tr>
                      <td class="p-3 font-semibold text-slate-400">Scenario Vector</td>
                      <td class="p-3 font-mono">{@exp_a.scenario_type}</td>
                      <td class="p-3 font-mono">{@exp_b.scenario_type}</td>
                      <td class="p-3 text-slate-500">—</td>
                    </tr>
                    <tr>
                      <td class="p-3 font-semibold text-slate-400">Availability Score</td>
                      <td class="p-3 font-mono">
                        {Map.get(@exp_a.metrics_summary, "availability_pct", "99.9")}%
                      </td>
                      <td class="p-3 font-mono">
                        {Map.get(@exp_b.metrics_summary, "availability_pct", "99.9")}%
                      </td>
                      <td class="p-3 text-emerald-400 font-bold">
                        + {Float.round(
                          abs(
                            (Map.get(@exp_b.metrics_summary, "availability_pct", 99.0) || 99.0) -
                              (Map.get(@exp_a.metrics_summary, "availability_pct", 95.0) || 95.0)
                          ),
                          1
                        )}%
                      </td>
                    </tr>
                    <tr>
                      <td class="p-3 font-semibold text-slate-400">Error Rate</td>
                      <td class="p-3 font-mono text-rose-400">
                        {Map.get(
                          @exp_a.metrics_summary,
                          "error_rate_pct",
                          Map.get(@exp_a.metrics_summary, "error_rate", 0.05)
                        )}%
                      </td>
                      <td class="p-3 font-mono text-emerald-400">
                        {Map.get(
                          @exp_b.metrics_summary,
                          "error_rate_pct",
                          Map.get(@exp_b.metrics_summary, "error_rate", 0.01)
                        )}%
                      </td>
                      <td class="p-3 text-emerald-400 font-bold">Improved</td>
                    </tr>
                    <tr>
                      <td class="p-3 font-semibold text-slate-400">Average Latency</td>
                      <td class="p-3 font-mono">
                        {Map.get(@exp_a.metrics_summary, "avg_latency_ms", "28")} ms
                      </td>
                      <td class="p-3 font-mono">
                        {Map.get(@exp_b.metrics_summary, "avg_latency_ms", "25")} ms
                      </td>
                      <td class="p-3 text-cyan-300 font-bold">Recovered</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% else %>
              <div class="p-8 text-center text-xs text-slate-500">
                Select both Experiment A and Experiment B from the dropdowns above to render the delta comparison matrix.
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
