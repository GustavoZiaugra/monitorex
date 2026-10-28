defmodule Monitorex.MixProject do
  use Mix.Project

  def project do
    [
      app: :monitorex,
      version: "0.8.1",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        plt_add_apps: [:mix]
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
      extra_applications: [:logger],
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
      {:phoenix_live_view, "~> 1.2"},
      {:igniter, "~> 0.8.5", optional: true},
      {:telemetry, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:esbuild, "~> 0.10.0", runtime: false},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      # Dev-only HTTP server for scripts/smoke_test.exs (Phoenix 1.8 adapter).
      # Replaces plug_cowboy, whose cowlib dependency has no fixed release for
      # CVE-2026-43966 yet.
      {:bandit, "~> 1.0", only: :dev},
      # Security floors for transitive dependencies. Optional so they don't
      # force an HTTP client / crypto stack on consumers; the version floor
      # still applies when another dependency (Phoenix, Finch, Req) pulls them.
      # CVE-2026-82728 / -82729 / -82672 / -91043 / -92103 / -94194.
      # 1.10.2 is the first release with the full HTTP/1 timeout fix set.
      {:mint, ">= 1.10.2 and < 2.0.0", optional: true},
      # Finch 0.23.0 can return a timed-out HTTP/1 connection to its pool when
      # Mint 1.11.0 is resolved; 0.24.0 handles the closed connection correctly.
      {:finch, ">= 0.24.0 and < 1.0.0", optional: true},
      # CVE-2026-105963
      {:plug_crypto, ">= 2.2.1 and < 3.0.0", optional: true},
      {:floki, "~> 0.38.1", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ex_doc, "~> 0.40.1", runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:hackney, "~> 4.5", optional: true},
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
