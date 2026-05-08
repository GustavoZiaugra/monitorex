defmodule Demo.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Seed demo data into ETS tables before starting children
    seed_demo_data()

    children = [
      DemoWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Demo.PubSub},
      DemoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Demo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp seed_demo_data do
    # Set LiveView signing salt for the Endpoint
    Application.put_env(:demo, DemoWeb.Endpoint,
      live_view: [signing_salt: "Yx8KmP4aLq2Rj7vB3tG9"]
    )

    # Seed ETS tables
    priv = Application.app_dir(:demo, "priv")
    path = Path.join(priv, "seed.exs")
    if File.exists?(path), do: Code.require_file(path)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
