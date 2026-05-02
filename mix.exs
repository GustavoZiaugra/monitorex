defmodule Monitorex.MixProject do
  use Mix.Project

  def project do
    [
      app: :monitorex,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Monitorex.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:esbuild, "~> 0.8", runtime: false},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:floki, "~> 0.37", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
