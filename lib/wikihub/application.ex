defmodule Wikihub.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WikihubWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:wikihub, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Wikihub.PubSub},
      # Parse + hold the wiki model, then watch the dirs for live updates
      Wikihub.Scanner,
      Wikihub.Watcher,
      WikihubWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Wikihub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WikihubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
