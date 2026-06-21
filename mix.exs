defmodule Monitorex.MixProject do
  use Mix.Project

  def project do
    [
      app: :monitorex,
      version: "0.6.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [preferred_envs: ["hex.publish": :prod]]
  end

  def application do
    [
      extra_applications: [:logger, :hackney],
      mod: {Monitorex.Application, []}
    ]
  end

  defp aliases do
    [
      "assets.build": ["tailwind monitorex", "esbuild monitorex"],
      setup: ["deps.get", "assets.build"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "guides/getting_started.md"],
      groups_for_extras: [guides: ~r/guides\/.?/],
      groups_for_modules: [
        Core: [
          Monitorex,
          Monitorex.Event,
          Monitorex.Router,
          Monitorex.Layouts,
          Monitorex.Assets,
          Monitorex.Authentication,
          Monitorex.Resolver
        ],
        "Data Pipeline": [
          Monitorex.Collector,
          Monitorex.EventHandler,
          Monitorex.Storage,
          Monitorex.Storage.Backend,
          Monitorex.Storage.ETS,
          Monitorex.Storage.SQLite,
          Monitorex.ClusterPage,
          Monitorex.Cluster
        ],
        Alerts: [
          Monitorex.Alerts,
          Monitorex.AlertHistory,
          Monitorex.Notifier,
          Monitorex.Notifiers.Slack,
          Monitorex.Notifiers.Discord,
          Monitorex.Notifiers.Email
        ],
        "UI Components": [
          Monitorex.Components.Core,
          Monitorex.Components.Live.Helpers,
          Monitorex.Components.Live.OutboundOverviewPage,
          Monitorex.Components.Live.OutboundRecentPage,
          Monitorex.Components.Live.HostDetailPage,
          Monitorex.Components.Live.InboundOverviewPage,
          Monitorex.Components.Live.InboundConsumersPage,
          Monitorex.Components.Live.InboundRecentPage,
          Monitorex.Components.Live.RouteDetailPage,
          Monitorex.DashboardLive
        ],
        Utilities: [
          Monitorex.UrlNormalizer,
          Monitorex.URLRedactor,
          Monitorex.ConsumerIdentifier
        ]
      ]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:telemetry, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:req_telemetry, "~> 0.1", optional: true},
      {:esbuild, "~> 0.10.0", runtime: false},
      {:tailwind, "~> 0.4.1", runtime: Mix.env() == :dev},
      {:plug_cowboy, "~> 2.7", only: :dev},
      {:floki, "~> 0.38.1", only: :test},
      {:ex_doc, "~> 0.40.1", runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:hackney, "~> 1.18", optional: true},
      {:gen_smtp, "~> 1.2", optional: true},
      {:exqlite, "~> 0.29", optional: true},
      {:meck, "~> 1.2", only: :test}
    ]
  end

  defp package do
    [
      name: "monitorex",
      description:
        "HTTP telemetry dashboard for Elixir/Phoenix — monitor outbound & inbound requests with LiveView",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/GustavoZiaugra/monitorex"
      },
      files: ~w(lib priv/static .formatter.exs mix.exs README.md LICENSE.md CHANGELOG.md)
    ]
  end
end
