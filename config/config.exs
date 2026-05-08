import Config

# Configure esbuild
config :esbuild,
  version: "0.25.4",
  monitorex: [
    args: ~w(assets/js/app.js --bundle --target=es2022 --outfile=priv/static/app.js),
    cd: Path.expand("..", __DIR__)
  ]

# Configure tailwind
config :tailwind,
  version: "4.1.12",
  monitorex: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]
