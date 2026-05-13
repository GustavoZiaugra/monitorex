# Getting Started

Add Monitorex to your Phoenix application in a few minutes.

## Installation

Add `monitorex` to your `mix.exs`:

```elixir
def deps do
  [
    {:monitorex, "~> 0.4.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Configuration

### 1. Configure sources

In `config/config.exs`, tell Monitorex which HTTP clients you want to monitor:

```elixir
config :monitorex, :sources, [:tesla, :finch, :req, :phoenix]
```

Available sources: `:tesla`, `:finch`, `:req`, `:phoenix`.  
Only include the ones you use. `:phoenix` monitors inbound traffic; the others monitor outbound requests.

### 2. Mount the dashboard in your router

Import `Monitorex.Router` and use the `http_dashboard` macro:

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use Phoenix.Router
  import Monitorex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
  end

  scope "/monitoring" do
    pipe_through :browser
    http_dashboard []
  end
end
```

### 3. Start your server

```bash
mix phx.server
```

Visit `/monitoring` to see your real-time HTTP telemetry dashboard.

## Next Steps

- **Authentication** — implement the `Monitorex.Resolver` behaviour to control dashboard access
- **Custom consumers** — configure consumer identification via `:consumer_fn`
- **Alert webhooks** — set up notifications for error rates, host down, and high latency
- **Request/response body capture** — enable body storage for detailed inspection
- **Cluster mode** — aggregate metrics across multiple BEAM nodes

See the [module documentation](`Monitorex`) for detailed configuration options.
