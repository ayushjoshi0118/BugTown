defmodule BugTown.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BugTownWeb.Telemetry,
      BugTown.Repo,
      {DNSCluster, query: Application.get_env(:bug_town, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BugTown.PubSub},
      BugTown.Engine.Coordinator,
      # Start to serve requests, typically the last entry
      BugTownWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BugTown.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BugTownWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
