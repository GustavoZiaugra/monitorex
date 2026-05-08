# Run with: mix run scripts/demo.exs
# Starts a Phoenix server with the Monitorex dashboard at http://localhost:4000

Application.put_env(:monitorex, :sources, [])
Application.put_env(:phoenix, :serve_endpoints, true)
Application.put_env(:monitorex, Monitorex.DemoEndpoint, [
  live_view: [signing_salt: "Rf3Pnq8iKj2Lx9vM0sAa"],
  render_errors: [view: Monitorex.ErrorView, accepts: ~w(html)]
])

# ── Router ──
defmodule Monitorex.DemoRouter do
  use Phoenix.Router
  import Monitorex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, {Monitorex.Layouts, :root}
    plug :protect_from_forgery
  end

  scope "/" do
    pipe_through :browser
    http_dashboard []
  end
end

# ── Minimal Phoenix Endpoint ──
defmodule Monitorex.DemoEndpoint do
  use Phoenix.Endpoint, otp_app: :monitorex

  @session_config [
    store: :cookie,
    key: "_demo_key",
    signing_salt: "demo"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_config]]

  plug Plug.Session,
    store: :cookie,
    key: "_demo_key",
    signing_salt: "demo"

  plug Monitorex.DemoRouter
end

# ── Seed Data ──
defmodule Monitorex.DemoSeeder do
  alias Monitorex.Event
  require Logger

  def seed do
    create_tables()
    seed_outbound()
    seed_inbound()
    Logger.info("Seeded demo data")
  end

  defp create_tables do
    tables = [
      :monitorex_outbound_hosts,
      :monitorex_outbound_endpoints,
      :monitorex_outbound_recent,
      :monitorex_outbound_duration_samples,
      :monitorex_inbound_routes,
      :monitorex_inbound_consumers,
      :monitorex_inbound_recent,
      :monitorex_inbound_duration_samples
    ]

    Enum.each(tables, fn name ->
      try do
        :ets.new(name, [:public, :named_table, :set, read_concurrency: true])
      rescue
        _ -> :ok
      end
    end)

    # Recent tables need ordered_set
    try do
      :ets.new(:monitorex_outbound_recent, [:public, :named_table, :ordered_set, read_concurrency: true])
    rescue
      _ -> :ok
    end
    try do
      :ets.new(:monitorex_inbound_recent, [:public, :named_table, :ordered_set, read_concurrency: true])
    rescue
      _ -> :ok
    end
    # Duration tables need bag
    try do
      :ets.new(:monitorex_outbound_duration_samples, [:public, :named_table, :bag, read_concurrency: true])
    rescue
      _ -> :ok
    end
    try do
      :ets.new(:monitorex_inbound_duration_samples, [:public, :named_table, :bag, read_concurrency: true])
    rescue
      _ -> :ok
    end
  end

  defp seed_outbound do
    hosts = [
      {"api.example.com", 342, 12, 15_200.0, 8_500_000, "Finch"},
      {"cdn.example.com", 1_891, 3, 48_500.0, 9_200_000, "Tesla"},
      {"auth.example.com", 156, 8, 6_800.0, 7_800_000, "Finch"},
      {"payments.example.com", 89, 15, 12_400.0, 7_500_000, "Tesla"},
      {"logs.example.com", 45, 0, 1_200.0, 9_500_000, "Finch"},
    ]

    endpoints = %{
      "api.example.com" => [
        {"/users", 120, 4, 3_600.0},
        {"/posts", 85, 2, 2_400.0},
        {"/comments", 62, 3, 1_800.0},
        {"/search", 45, 2, 4_200.0},
        {"/upload", 30, 1, 3_200.0},
      ],
      "cdn.example.com" => [
        {"/images/*", 1_200, 1, 28_000.0},
        {"/assets/*", 450, 1, 14_000.0},
        {"/videos/*", 241, 1, 6_500.0},
      ],
      "auth.example.com" => [
        {"/login", 60, 2, 2_800.0},
        {"/token/refresh", 50, 3, 2_200.0},
        {"/logout", 30, 1, 1_000.0},
        {"/verify", 16, 2, 800.0},
      ],
      "payments.example.com" => [
        {"/charge", 30, 8, 5_200.0},
        {"/refund", 25, 3, 3_600.0},
        {"/subscription", 20, 2, 2_200.0},
        {"/invoice", 14, 2, 1_400.0},
      ],
      "logs.example.com" => [
        {"/ingest", 30, 0, 800.0},
        {"/search", 15, 0, 400.0},
      ],
    }

    # Seed host aggregates
    Enum.each(hosts, fn {host, requests, errors, total_duration, last_seen, client} ->
      :ets.insert(:monitorex_outbound_hosts, {host, %{
        requests: requests,
        errors: errors,
        total_duration: total_duration,
        last_seen: last_seen,
        client: client
      }})
    end)

    # Seed endpoint aggregates
    Enum.each(endpoints, fn {host, eps} ->
      Enum.each(eps, fn {path, requests, errors, total_duration} ->
        :ets.insert(:monitorex_outbound_endpoints, {{host, path}, %{
          requests: requests,
          errors: errors,
          total_duration: total_duration,
          last_seen: System.system_time(:millisecond)
        }})
      end)
    end)

    # Seed recent events with various status codes
    now = System.system_time(:millisecond)

    recent_events = [
      {"api.example.com", "/users", "GET", 200, 45.2, 2_000_000},
      {"api.example.com", "/users", "GET", 200, 12.8, 1_950_000},
      {"api.example.com", "/posts", "POST", 201, 120.5, 1_900_000},
      {"cdn.example.com", "/images/*", "GET", 200, 3.2, 1_850_000},
      {"cdn.example.com", "/assets/*", "GET", 304, 1.1, 1_800_000},
      {"auth.example.com", "/login", "POST", 200, 85.0, 1_750_000},
      {"api.example.com", "/search", "GET", 500, 2500.0, 1_700_000},
      {"api.example.com", "/upload", "POST", 502, 3000.0, 1_650_000},
      {"payments.example.com", "/charge", "POST", 200, 340.0, 1_600_000},
      {"payments.example.com", "/charge", "POST", 402, 150.0, 1_550_000},
      {"payments.example.com", "/refund", "POST", 500, 2800.0, 1_500_000},
      {"api.example.com", "/comments", "GET", 200, 22.4, 1_450_000},
      {"auth.example.com", "/token/refresh", "POST", 200, 65.3, 1_400_000},
      {"cdn.example.com", "/videos/*", "GET", 200, 450.0, 1_350_000},
      {"api.example.com", "/users/1", "GET", 200, 8.9, 1_300_000},
      {"api.example.com", "/posts", "GET", 200, 15.6, 1_250_000},
      {"auth.example.com", "/login", "POST", 401, 3.2, 1_200_000},
      {"logs.example.com", "/ingest", "POST", 200, 25.0, 1_150_000},
      {"api.example.com", "/comments", "POST", 201, 35.8, 1_100_000},
      {"cdn.example.com", "/images/logo.png", "GET", 200, 2.1, 1_050_000},
      {"api.example.com", "/users", "GET", 200, 18.3, 1_000_000},
      {"payments.example.com", "/subscription", "POST", 200, 200.5, 950_000},
      {"api.example.com", "/search", "GET", 404, 1.5, 900_000},
      {"api.example.com", "/upload", "POST", 200, 520.0, 850_000},
      {"cdn.example.com", "/assets/app.js", "GET", 200, 1.8, 800_000},
    ]

    Enum.each(recent_events, fn {host, path, method, status, duration_ms, ts_ago} ->
      ts = now - ts_ago
      event = %Event{
        source: :demo,
        direction: :outbound,
        method: method,
        host: host,
        path: path,
        full_url: "https://#{host}#{path}",
        status: status,
        status_class: Event.classify_status(status),
        duration_ms: duration_ms,
        consumer: nil,
        error: if(status >= 500, do: "HTTP #{status}", else: nil),
        timestamp: ts,
        dedup_key: {host, path, method, ts}
      }
      :ets.insert(:monitorex_outbound_recent, {ts, event})
      :ets.insert(:monitorex_outbound_duration_samples, {host, duration_ms})
    end)
  end

  defp seed_inbound do
    routes = [
      {"GET:/api/users", 345, 8, 12_400.0, 8_000_000},
      {"POST:/api/users", 120, 5, 18_500.0, 7_800_000},
      {"GET:/api/posts", 280, 4, 9_800.0, 8_200_000},
      {"POST:/api/posts", 95, 2, 15_200.0, 7_500_000},
      {"GET:/api/search", 180, 12, 25_000.0, 7_900_000},
      {"DELETE:/api/comments", 45, 1, 2_800.0, 7_000_000},
      {"PUT:/api/users/:id", 78, 3, 6_500.0, 7_400_000},
    ]

    Enum.each(routes, fn {key, requests, errors, total_duration, last_seen} ->
      :ets.insert(:monitorex_inbound_routes, {key, %{
        requests: requests,
        errors: errors,
        total_duration: total_duration,
        last_seen: last_seen
      }})
    end)

    consumers = [
      {"myapp-web", 450, 10, 18_000.0, 8_100_000},
      {"myapp-worker", 320, 8, 42_000.0, 7_900_000},
      {"myapp-cron", 85, 2, 3_400.0, 7_000_000},
      {"partner-integration", 120, 15, 28_000.0, 7_800_000},
    ]

    Enum.each(consumers, fn {name, requests, errors, total_duration, last_seen} ->
      :ets.insert(:monitorex_inbound_consumers, {name, %{
        requests: requests,
        errors: errors,
        total_duration: total_duration,
        last_seen: last_seen
      }})
    end)
  end
end

# ── Error View ──
defmodule Monitorex.ErrorView do
  def render("500.html", _assigns), do: "Internal Server Error"
  def render("404.html", _assigns), do: "Not Found"
  def render(template, _assigns), do: "Error: #{template}"
end

# ── Main ──
Logger.configure(level: :info)

Monitorex.DemoSeeder.seed()

# Configure CORS for LiveView
config = [
  server: true,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(32)),
  debug_errors: true,
]

# Need to cache the assets content before starting
_ = Monitorex.Assets.css_hash()
_ = Monitorex.Assets.js_hash()

{:ok, _pid} = Monitorex.DemoEndpoint.start_link(config)

IO.puts("""

╔══════════════════════════════════════════╗
║         Monitorex Dashboard             ║
║                                          ║
║   http://localhost:4000                  ║
║   http://localhost:4000/inbound          ║
║   http://localhost:4000/outbound_recent  ║
║   http://localhost:4000/host/api.ex...  ║
║   http://localhost:4000/route/GET:...   ║
║                                          ║
║   Press Ctrl+C to stop                  ║
╚══════════════════════════════════════════╝
""")

# Keep running
Process.sleep(:infinity)
