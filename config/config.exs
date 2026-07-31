import Config

# Configure esbuild
config :esbuild,
  version: "0.25.4",
  monitorex: [
    args: ~w(
      assets/js/app.js
      --bundle
      --target=es2022
      --outfile=priv/static/app.js
      --alias:phoenix=./deps/phoenix/priv/static/phoenix.mjs
      --alias:phoenix_live_view=./deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js
    ),
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

if config_env() == :test do
  config :monitorex, Monitorex.TestEndpoint,
    url: [host: "localhost"],
    server: false,
    live_view: [signing_salt: "test_salt_monitorex"],
    secret_key_base: String.duplicate("a", 64)

  config :monitorex, Monitorex.PubSub,
    name: Monitorex.PubSub,
    adapter: Phoenix.PubSub.PG2
end
