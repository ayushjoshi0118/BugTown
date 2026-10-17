defmodule BugTownWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BugTownWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil
  attr :current_page, :atom, default: :command_center
  attr :sim_state, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    sim =
      assigns[:sim_state] ||
        %{
          status: :running,
          speed: 1.0,
          sim_time_seconds: 0,
          global_metrics: %{
            health_pct: 100.0,
            total_rps: 120.0,
            avg_latency_ms: 24.5,
            error_rate: 0.001,
            active_incidents_count: 0
          },
          bugs: %{}
        }

    assigns = assign(assigns, :sim, sim)

    ~H"""
    <div class="min-h-screen bg-[#080B12] text-slate-200 flex flex-col font-mono selection:bg-cyan-500/30 selection:text-cyan-300">
      <%!-- Top Mission-Control Header Bar --%>
      <header class="h-16 border-b border-[#263244] bg-[#111722]/90 backdrop-blur-md px-4 sm:px-6 flex items-center justify-between sticky top-0 z-40">
        <div class="flex items-center gap-6">
          <a href="/" class="flex items-center gap-2.5 group">
            <div class="w-8 h-8 rounded-lg bg-cyan-950/80 border border-cyan-500/40 flex items-center justify-center text-cyan-400 group-hover:border-cyan-400 transition-all shadow-[0_0_12px_rgba(0,240,255,0.25)]">
              <.icon name="hero-cpu-chip" class="w-5 h-5 text-cyan-400 animate-pulse" />
            </div>
            <div class="flex flex-col">
              <span class="text-base font-bold tracking-wider text-cyan-400 group-hover:text-cyan-300 transition-colors flex items-center gap-1.5">
                BUGTOWN
                <span class="text-[10px] uppercase font-normal px-1.5 py-0.2 rounded bg-cyan-950 border border-cyan-800 text-cyan-300">Sim v1.0</span>
              </span>
              <span class="text-[10px] text-slate-400 tracking-tight">Living Software Bug Simulator</span>
            </div>
          </a>

          <%!-- Simulation Status Badge --%>
          <div class="hidden md:flex items-center gap-2 pl-4 border-l border-[#263244]">
            <div class={[
              "flex items-center gap-2 px-2.5 py-1 rounded-md text-xs font-medium border",
              @sim.status == :running && "bg-emerald-950/40 border-emerald-500/30 text-emerald-400",
              @sim.status == :paused && "bg-amber-950/40 border-amber-500/30 text-amber-400",
              @sim.status == :stopped && "bg-rose-950/40 border-rose-500/30 text-rose-400"
            ]}>
              <span class={[
                "w-2 h-2 rounded-full",
                @sim.status == :running && "bg-emerald-400 animate-pulse",
                @sim.status == :paused && "bg-amber-400",
                @sim.status == :stopped && "bg-rose-400"
              ]}></span>
              <span class="uppercase tracking-wider font-semibold text-[11px]">{to_string(@sim.status)}</span>
            </div>

            <div class="flex items-center gap-1 text-[11px] text-slate-400 bg-[#161E2C] px-2 py-1 rounded border border-[#263244]">
              <.icon name="hero-clock" class="w-3.5 h-3.5 text-slate-400" />
              <span>T+{div(@sim.sim_time_seconds, 60)}m {rem(@sim.sim_time_seconds, 60)}s</span>
            </div>
          </div>
        </div>

        <%!-- Live Key Telemetry Ticker --%>
        <div class="hidden lg:flex items-center gap-4 text-xs">
          <div class="flex flex-col">
            <span class="text-[10px] uppercase text-slate-400">Health</span>
            <span class={[
              "font-bold",
              @sim.global_metrics.health_pct >= 90 && "text-emerald-400",
              (@sim.global_metrics.health_pct < 90 and @sim.global_metrics.health_pct >= 60) &&
                "text-amber-400",
              @sim.global_metrics.health_pct < 60 && "text-rose-400"
            ]}>
              {@sim.global_metrics.health_pct}%
            </span>
          </div>

          <div class="h-6 w-px bg-[#263244]"></div>

          <div class="flex flex-col">
            <span class="text-[10px] uppercase text-slate-400">Throughput</span>
            <span class="font-bold text-cyan-300">{@sim.global_metrics.total_rps} req/s</span>
          </div>

          <div class="h-6 w-px bg-[#263244]"></div>

          <div class="flex flex-col">
            <span class="text-[10px] uppercase text-slate-400">Avg Latency</span>
            <span class={[
              "font-bold",
              @sim.global_metrics.avg_latency_ms < 50 && "text-slate-200",
              (@sim.global_metrics.avg_latency_ms >= 50 and @sim.global_metrics.avg_latency_ms < 150) &&
                "text-amber-400",
              @sim.global_metrics.avg_latency_ms >= 150 && "text-rose-400"
            ]}>
              {@sim.global_metrics.avg_latency_ms} ms
            </span>
          </div>

          <div class="h-6 w-px bg-[#263244]"></div>

          <div class="flex flex-col">
            <span class="text-[10px] uppercase text-slate-400">Error Rate</span>
            <span class={[
              "font-bold",
              @sim.global_metrics.error_rate < 0.02 && "text-slate-200",
              @sim.global_metrics.error_rate >= 0.02 && "text-rose-400"
            ]}>
              {Float.round(@sim.global_metrics.error_rate * 100, 2)}%
            </span>
          </div>

          <div class="h-6 w-px bg-[#263244]"></div>

          <div class="flex flex-col">
            <span class="text-[10px] uppercase text-slate-400">Living Bugs</span>
            <span class="font-bold text-amber-400 flex items-center gap-1">
              <.icon name="hero-bug-ant" class="w-3.5 h-3.5" />
              {map_size(@sim.bugs)}
            </span>
          </div>
        </div>

        <%!-- Header Sim Controls --%>
        <div class="flex items-center gap-2">
          <%= if @sim.status == :running do %>
            <button
              phx-click="pause_sim"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded bg-amber-950/60 hover:bg-amber-900/60 border border-amber-600/40 text-amber-300 text-xs font-semibold transition cursor-pointer"
              title="Pause Simulation"
            >
              <.icon name="hero-pause" class="w-3.5 h-3.5" />
              <span class="hidden sm:inline">Pause</span>
            </button>
          <% else %>
            <button
              phx-click="resume_sim"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded bg-emerald-950/60 hover:bg-emerald-900/60 border border-emerald-600/40 text-emerald-300 text-xs font-semibold transition cursor-pointer"
              title="Resume Simulation"
            >
              <.icon name="hero-play" class="w-3.5 h-3.5" />
              <span class="hidden sm:inline">Resume</span>
            </button>
          <% end %>

          <button
            phx-click="reset_sim"
            data-confirm="Reset simulation state to pristine baseline?"
            class="flex items-center gap-1.5 px-3 py-1.5 rounded bg-[#161E2C] hover:bg-[#202B3D] border border-[#263244] text-slate-300 hover:text-white text-xs font-semibold transition cursor-pointer"
            title="Reset to Baseline"
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" />
            <span class="hidden sm:inline">Reset</span>
          </button>

          <%!-- Speed Picker dropdown --%>
          <div class="flex items-center bg-[#111722] border border-[#263244] rounded p-0.5 text-xs text-slate-300">
            <button
              phx-click="set_speed"
              phx-value-speed="0.5"
              class={[
                "px-2 py-0.5 rounded cursor-pointer",
                @sim.speed == 0.5 && "bg-cyan-500/20 text-cyan-300 font-bold"
              ]}
            >0.5x</button>
            <button
              phx-click="set_speed"
              phx-value-speed="1.0"
              class={[
                "px-2 py-0.5 rounded cursor-pointer",
                @sim.speed == 1.0 && "bg-cyan-500/20 text-cyan-300 font-bold"
              ]}
            >1x</button>
            <button
              phx-click="set_speed"
              phx-value-speed="2.0"
              class={[
                "px-2 py-0.5 rounded cursor-pointer",
                @sim.speed == 2.0 && "bg-cyan-500/20 text-cyan-300 font-bold"
              ]}
            >2x</button>
          </div>
        </div>
      </header>

      <%!-- Main Layout with Sidebar and Content --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Sidebar Navigation --%>
        <aside class="w-64 border-r border-[#263244] bg-[#0C101A] flex flex-col justify-between shrink-0 hidden md:flex">
          <div class="p-3 space-y-1">
            <div class="px-3 py-2 text-[10px] font-semibold text-slate-400 uppercase tracking-widest">
              Observability & Ops
            </div>

            <.link
              navigate={~p"/"}
              class={[
                "flex items-center justify-between px-3 py-2 rounded-md text-xs font-medium transition group",
                @current_page == :command_center &&
                  "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30 shadow-[0_0_8px_rgba(0,240,255,0.1)]",
                @current_page != :command_center &&
                  "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <div class="flex items-center gap-2.5">
                <.icon name="hero-bolt" class="w-4 h-4" />
                <span>Command Center</span>
              </div>
              <span class="text-[10px] px-1.5 py-0.5 rounded bg-[#111722] border border-[#263244] text-slate-400">LIVE</span>
            </.link>

            <.link
              navigate={~p"/topology"}
              class={[
                "flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :topology && "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :topology && "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <.icon name="hero-share" class="w-4 h-4" />
              <span>Topology Explorer</span>
            </.link>

            <.link
              navigate={~p"/faults"}
              class={[
                "flex items-center justify-between px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :faults && "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :faults && "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <div class="flex items-center gap-2.5">
                <.icon name="hero-fire" class="w-4 h-4" />
                <span>Fault Injection Lab</span>
              </div>
              <%= if map_size(@sim.active_faults) > 0 do %>
                <span class="px-1.5 py-0.2 rounded text-[10px] bg-rose-950 border border-rose-500/40 text-rose-300">
                  {map_size(@sim.active_faults)}
                </span>
              <% end %>
            </.link>

            <.link
              navigate={~p"/incidents"}
              class={[
                "flex items-center justify-between px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :incidents &&
                  "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :incidents &&
                  "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <div class="flex items-center gap-2.5">
                <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                <span>Incidents</span>
              </div>
              <%= if Map.get(@sim.global_metrics, :active_incidents_count, 0) > 0 do %>
                <span class="px-1.5 py-0.2 rounded text-[10px] bg-rose-950 border border-rose-500/40 text-rose-300 font-bold animate-pulse">
                  {Map.get(@sim.global_metrics, :active_incidents_count, 0)}
                </span>
              <% end %>
            </.link>

            <.link
              navigate={~p"/observability"}
              class={[
                "flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :observability &&
                  "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :observability &&
                  "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <.icon name="hero-chart-bar" class="w-4 h-4" />
              <span>Observability</span>
            </.link>

            <div class="pt-4 px-3 py-2 text-[10px] font-semibold text-slate-400 uppercase tracking-widest">
              Chaos & Resilience
            </div>

            <.link
              navigate={~p"/experiments"}
              class={[
                "flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :experiments &&
                  "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :experiments &&
                  "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <.icon name="hero-beaker" class="w-4 h-4" />
              <span>Chaos Experiments</span>
            </.link>

            <.link
              navigate={~p"/recovery"}
              class={[
                "flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :recovery && "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :recovery && "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <.icon name="hero-shield-check" class="w-4 h-4" />
              <span>Recovery Center</span>
            </.link>

            <.link
              navigate={~p"/settings"}
              class={[
                "flex items-center gap-2.5 px-3 py-2 rounded-md text-xs font-medium transition",
                @current_page == :settings && "bg-cyan-950/60 text-cyan-400 border border-cyan-500/30",
                @current_page != :settings && "text-slate-400 hover:text-slate-200 hover:bg-[#161E2C]"
              ]}
            >
              <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
              <span>Settings</span>
            </.link>
          </div>

          <%!-- Sidebar Bottom System Card --%>
          <div class="p-4 border-t border-[#263244] bg-[#0E131F]/50">
            <div class="flex items-center justify-between text-[11px] text-slate-400 mb-2">
              <span>PostgreSQL Store</span>
              <span class="text-emerald-400 flex items-center gap-1">
                <span class="w-1.5 h-1.5 rounded-full bg-emerald-400"></span> Connected
              </span>
            </div>
            <div class="text-[10px] text-slate-500 truncate">
              Seed: {@sim.seed} · Ticks: {@sim.tick_count}
            </div>
          </div>
        </aside>

        <%!-- Content Viewport --%>
        <main class="flex-1 overflow-y-auto bg-[#080B12] tech-grid flex flex-col">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
