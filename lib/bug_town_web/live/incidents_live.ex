defmodule BugTownWeb.IncidentsLive do
  use BugTownWeb, :live_view
  alias BugTownWeb.LiveHelper
  alias BugTown.Engine.Coordinator

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveHelper.setup_sim(:incidents, "Incidents · BugTown")
      |> assign(:selected_incident_id, nil)
      |> assign(:filter_status, "all")
      |> assign(:notes_input, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("select_incident", %{"id" => id}, socket) do
    current = socket.assigns.selected_incident_id
    new_sel = if current == id, do: nil, else: id
    {:noreply, assign(socket, :selected_incident_id, new_sel)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, assign(socket, :filter_status, status)}
  end

  @impl true
  def handle_event("notes_change", %{"notes" => notes}, socket) do
    {:noreply, assign(socket, :notes_input, notes)}
  end

  @impl true
  def handle_event("acknowledge_incident", %{"id" => id}, socket) do
    notes = socket.assigns.notes_input

    case Coordinator.acknowledge_incident(id, notes) do
      {:ok, inc} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Acknowledged incident #{inc.code}. Status updated to investigating."
         )
         |> assign(:notes_input, "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to acknowledge incident.")}
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
    filtered_incidents =
      assigns.sim_state.incidents
      |> Map.values()
      |> Enum.filter(fn inc ->
        assigns.filter_status == "all" or inc.status == assigns.filter_status
      end)
      |> Enum.sort_by(& &1.created_at_tick, :desc)

    assigns = assign(assigns, :filtered_incidents, filtered_incidents)

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
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-rose-400" />
              <span>INCIDENT MANAGEMENT & ROOT CAUSE CORRELATION</span>
            </h1>
            <p class="text-xs text-slate-400 mt-1">
              Automated SLO anomaly detection, alert deduplication, and investigation runbooks
            </p>
          </div>

          <%!-- Status Filter Tabs --%>
          <div class="flex items-center bg-[#111722] border border-[#263244] rounded p-0.5 text-xs">
            <%= for st <- ["all", "open", "investigating", "mitigating", "resolved"] do %>
              <button
                phx-click="filter_status"
                phx-value-status={st}
                class={[
                  "px-3 py-1 rounded cursor-pointer capitalize font-medium",
                  @filter_status == st && "bg-cyan-500/20 text-cyan-300 font-bold"
                ]}
              >
                {st}
              </button>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <%!-- Incidents Table (2 Cols) --%>
          <div class="lg:col-span-2 rounded-xl bg-[#111722] border border-[#263244] overflow-hidden shadow-xl">
            <div class="px-5 py-3 border-b border-[#263244] bg-[#161E2C]/50 flex items-center justify-between text-xs">
              <span class="font-bold text-slate-200 uppercase tracking-wider">
                Incident Register ({length(@filtered_incidents)})
              </span>
              <span class="text-slate-400">Click row to inspect timeline and diagnostic trail</span>
            </div>

            <div class="divide-y divide-[#263244] max-h-[620px] overflow-y-auto">
              <%= if @filtered_incidents == [] do %>
                <div class="p-12 text-center text-xs text-slate-500">
                  <.icon name="hero-check-circle" class="w-10 h-10 mx-auto mb-2 text-emerald-500/40" />
                  No incidents match the selected filter.
                </div>
              <% else %>
                <%= for inc <- @filtered_incidents do %>
                  <% is_selected = @selected_incident_id == inc.id %>
                  <div
                    phx-click="select_incident"
                    phx-value-id={inc.id}
                    class={[
                      "p-4 cursor-pointer transition flex items-start justify-between gap-4 text-xs",
                      is_selected && "bg-[#1E2738] border-l-4 border-l-cyan-400",
                      not is_selected && "hover:bg-[#161E2C]/60 border-l-4 border-l-transparent"
                    ]}
                  >
                    <div class="space-y-1.5 flex-1">
                      <div class="flex items-center gap-2">
                        <span class="font-mono font-bold text-white text-sm">{inc.code}</span>
                        <span class={[
                          "px-2 py-0.2 rounded text-[10px] uppercase font-bold",
                          inc.severity == "critical" &&
                            "bg-rose-950 text-rose-300 border border-rose-500/30",
                          inc.severity == "high" && "bg-red-950 text-red-300 border border-red-500/30",
                          inc.severity == "medium" &&
                            "bg-amber-950 text-amber-300 border border-amber-500/30",
                          inc.severity == "low" &&
                            "bg-slate-800 text-slate-300 border border-slate-600/30"
                        ]}>
                          {inc.severity}
                        </span>
                        <span class={[
                          "px-2 py-0.2 rounded text-[10px] uppercase font-semibold",
                          inc.status == "open" && "bg-rose-950/60 text-rose-300",
                          inc.status == "investigating" && "bg-amber-950/60 text-amber-300",
                          inc.status == "mitigating" && "bg-blue-950/60 text-blue-300",
                          inc.status == "resolved" && "bg-emerald-950/60 text-emerald-300"
                        ]}>
                          {inc.status}
                        </span>
                      </div>

                      <div class="font-semibold text-slate-100">{inc.title}</div>
                      <div class="text-[11px] text-slate-400">
                        Affected Services:
                        <span class="text-cyan-300 font-mono">{Enum.join(inc.affected_services, ", ")}</span>
                      </div>
                    </div>

                    <div class="text-right text-[10px] text-slate-500 shrink-0 space-y-1">
                      <div>Triggered: T+{inc.created_at_tick}</div>
                      <%= if inc.resolved_at_tick do %>
                        <div class="text-emerald-400">Resolved: T+{inc.resolved_at_tick}</div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Incident Detail Inspector (Right Column) --%>
          <div class="rounded-xl bg-[#111722] border border-[#263244] p-5 shadow-xl flex flex-col justify-between">
            <%= if @selected_incident_id do %>
              <% inc = Map.get(@sim_state.incidents, @selected_incident_id) %>
              <%= if inc do %>
                <div class="space-y-4 text-xs">
                  <div class="pb-3 border-b border-[#263244]">
                    <div class="flex items-center justify-between">
                      <span class="font-mono text-cyan-400 font-bold">{inc.code}</span>
                      <span class="px-2 py-0.5 rounded text-[10px] uppercase font-bold bg-[#161E2C] text-slate-300 border border-[#263244]">
                        {inc.status}
                      </span>
                    </div>
                    <h3 class="text-base font-bold text-white mt-1">{inc.title}</h3>
                    <p class="text-slate-400 text-[11px] mt-1">
                      <strong>Root Cause:</strong> {inc.root_cause}
                    </p>
                  </div>

                  <div>
                    <h4 class="font-bold text-slate-300 mb-2">Event Timeline:</h4>
                    <div class="space-y-2 max-h-48 overflow-y-auto">
                      <%= for ev <- inc.timeline_events do %>
                        <div class="p-2 rounded bg-[#161E2C] border border-[#263244] text-slate-300 text-[11px]">
                          <span class="text-cyan-400 font-mono">T+{ev.tick}:</span> {ev.event}
                        </div>
                      <% end %>
                    </div>
                  </div>

                  <%= if inc.notes && inc.notes != "" do %>
                    <div class="p-3 rounded bg-[#0C101A] border border-[#263244]">
                      <span class="text-[10px] font-bold uppercase text-slate-400">Investigation Notes:</span>
                      <p class="text-slate-200 text-xs mt-1">{inc.notes}</p>
                    </div>
                  <% end %>

                  <%= if inc.status in ["open", "investigating"] do %>
                    <form
                      phx-submit="acknowledge_incident"
                      phx-value-id={inc.id}
                      class="space-y-2 pt-2 border-t border-[#263244]"
                    >
                      <label class="block text-slate-300 text-[11px] font-bold">Add Investigation Log / Notes:</label>
                      <input
                        type="text"
                        name="notes"
                        phx-change="notes_change"
                        value={@notes_input}
                        placeholder="e.g. Inspecting Postgres locks; deploying circuit breaker"
                        class="w-full bg-[#161E2C] border border-[#263244] rounded px-3 py-2 text-xs text-white"
                      />
                      <button
                        type="submit"
                        class="w-full py-2 rounded bg-amber-600 hover:bg-amber-500 text-white font-bold text-xs uppercase tracking-wider transition cursor-pointer"
                      >
                        Acknowledge & Mark Investigating
                      </button>
                    </form>
                  <% end %>
                </div>

                <div class="pt-4 border-t border-[#263244]">
                  <.link
                    navigate={~p"/recovery"}
                    class="block text-center w-full py-2 rounded bg-emerald-950 hover:bg-emerald-900 border border-emerald-500/40 text-emerald-300 font-semibold"
                  >
                    Open Recovery Center &rarr;
                  </.link>
                </div>
              <% end %>
            <% else %>
              <div class="text-center py-20 text-slate-500 text-xs">
                <.icon name="hero-cursor-arrow-rays" class="w-8 h-8 mx-auto mb-2 opacity-50" />
                Select an incident from the register to inspect its complete timeline and root-cause evidence.
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
