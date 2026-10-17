defmodule BugTownWeb.LiveHelper do
  @moduledoc """
  Common helpers for BugTown LiveViews: PubSub subscription, sim state hydration,
  and simulation control event handlers.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  alias BugTown.Engine.Coordinator

  def setup_sim(socket, page_atom, page_title) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BugTown.PubSub, "simulation:state")
    end

    state = Coordinator.get_state()

    socket
    |> assign(:sim_state, state)
    |> assign(:current_page, page_atom)
    |> assign(:page_title, page_title)
    |> assign(:current_scope, nil)
  end

  def handle_common_event("start_sim", _params, socket) do
    {:ok, state} = Coordinator.start_sim()
    {:noreply, assign(socket, :sim_state, state)}
  end

  def handle_common_event("pause_sim", _params, socket) do
    {:ok, state} = Coordinator.pause_sim()
    {:noreply, assign(socket, :sim_state, state)}
  end

  def handle_common_event("resume_sim", _params, socket) do
    {:ok, state} = Coordinator.resume_sim()
    {:noreply, assign(socket, :sim_state, state)}
  end

  def handle_common_event("reset_sim", _params, socket) do
    {:ok, state} = Coordinator.reset_sim()

    {:noreply,
     assign(socket, :sim_state, state)
     |> put_flash(:info, "Simulation reset to pristine baseline.")}
  end

  def handle_common_event("set_speed", %{"speed" => speed_str}, socket) do
    case Float.parse(speed_str) do
      {speed, _} when speed > 0 ->
        {:ok, state} = Coordinator.set_speed(speed)
        {:noreply, assign(socket, :sim_state, state)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_common_event(_event, _params, socket) do
    {:noreply, socket}
  end

  def handle_sim_info({:simulation_state_updated, state}, socket) do
    {:noreply, assign(socket, :sim_state, state)}
  end

  def handle_sim_info(_msg, socket) do
    {:noreply, socket}
  end
end
