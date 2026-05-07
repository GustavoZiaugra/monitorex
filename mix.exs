defmodule Monitorex.MixProject do
  use Mix.Project

  def project do
    [
      app: :monitorex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Monitorex.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:telemetry, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:esbuild, "~> 0.10.0", runtime: false},
      {:tailwind, "~> 0.4.1", runtime: Mix.env() == :dev},
      {:floki, "~> 0.38.1", only: :test},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end
end
