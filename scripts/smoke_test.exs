# Run with: mix run scripts/smoke_test.exs
# Smoke test that verifies every HTTP route in the Monitorex dashboard.
# Starts a real Phoenix server, seeds ETS data, then hits every route.
# Exits 0 on success, 1 on any failure.

Application.put_env(:monitorex, :sources, [])
Application.put_env(:phoenix, :serve_endpoints, true)
Application.put_env(:monitorex, Monitorex.SmokeEndpoint, [
  live_view: [signing_salt: "smoke_test_salt_abc123"],
  render_errors: [view: Monitorex.SmokeErrorView, accepts: ~w(html)]
])

# ── Router ──
defmodule Monitorex.SmokeRouter do
  use Phoenix.Router
  import Monitorex.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, {Monitorex.Layouts, :root}
    plug :protect_from_forgery
  end

  scope "/" do
    pipe_through :browser
    http_dashboard []
  end
end

# ── Minimal Phoenix Endpoint ──
defmodule Monitorex.SmokeEndpoint do
  use Phoenix.Endpoint, otp_app: :monitorex

  @session_config [
    store: :cookie,
    key: "_smoke_key",
    signing_salt: "smoke_salt"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_config]]

  plug Plug.Session, @session_config

  plug Monitorex.SmokeRouter
end

# ── Error View ──
defmodule Monitorex.SmokeErrorView do
  def render("500.html", _), do: "Internal Server Error"
  def render("404.html", _), do: "Not Found"
  def render(t, _), do: "Error: #{t}"
end

# ── Seeder ──
defmodule Monitorex.SmokeSeeder do
  alias Monitorex.Event

  @ets_tables [
    :monitorex_outbound_hosts, :monitorex_outbound_endpoints,
    :monitorex_outbound_recent, :monitorex_outbound_duration_samples,
    :monitorex_inbound_routes, :monitorex_inbound_consumers,
    :monitorex_inbound_recent, :monitorex_inbound_duration_samples,
    :monitorex_slow_outbound, :monitorex_slow_inbound, :monitorex_dedup
  ]

  @type_map %{
    monitorex_outbound_recent: :ordered_set, monitorex_inbound_recent: :ordered_set,
    monitorex_outbound_duration_samples: :bag, monitorex_inbound_duration_samples: :bag,
    monitorex_slow_outbound: :ordered_set, monitorex_slow_inbound: :ordered_set
  }

  def seed do
    reset_ets()
    seed_outbound()
  end

  defp reset_ets do
    Enum.each(@ets_tables, fn t -> try do :ets.delete(t) rescue _ -> :ok end end)
    Enum.each(@ets_tables, fn t ->
      type = Map.get(@type_map, t, :set)
      try do :ets.new(t, [:public, :named_table, type, read_concurrency: true]) rescue _ -> :ok end
    end)
  end

  defp seed_outbound do
    now = System.system_time(:millisecond)

    # Host aggregates
    [
      {"api.example.com", 342, 12, 15_200.0, now - 60_000, "Finch"},
      {"cdn.example.com", 1_891, 3, 48_500.0, now - 120_000, "Tesla"},
      {"auth.example.com", 156, 8, 6_800.0, now - 300_000, "Finch"},
    ]
    |> Enum.each(fn {h, r, e, td, ls, c} ->
      :ets.insert(:monitorex_outbound_hosts, {h, %{requests: r, errors: e, total_duration: td, last_seen: ls, client: c}})
    end)

    # Endpoint aggregates
    %{
      "api.example.com" => [{"/users", 120, 4, 3_600.0}, {"/posts", 85, 2, 2_400.0}, {"/search", 45, 2, 4_200.0}],
      "cdn.example.com" => [{"/images/*", 1_200, 1, 28_000.0}, {"/assets/*", 450, 1, 14_000.0}],
      "auth.example.com" => [{"/login", 60, 2, 2_800.0}, {"/token/refresh", 50, 3, 2_200.0}],
    }
    |> Enum.each(fn {host, list} ->
      list |> Enum.each(fn {path, r, e, td} ->
        :ets.insert(:monitorex_outbound_endpoints, {{host, path}, %{requests: r, errors: e, total_duration: td, last_seen: now}})
      end)
    end)

    # Inbound routes
    [
      {"GET:/api/users", 345, 8, 12_400.0, now},
      {"POST:/api/users", 120, 5, 18_500.0, now},
      {"GET:/api/search", 180, 12, 25_000.0, now},
    ]
    |> Enum.each(fn {key, r, e, td, ls} ->
      :ets.insert(:monitorex_inbound_routes, {key, %{requests: r, errors: e, total_duration: td, last_seen: ls}})
    end)

    # Consumers
    [
      {"myapp-web", 450, 10, 18_000.0, now},
      {"myapp-worker", 320, 8, 42_000.0, now},
    ]
    |> Enum.each(fn {name, r, e, td, ls} ->
      :ets.insert(:monitorex_inbound_consumers, {name, %{requests: r, errors: e, total_duration: td, last_seen: ls}})
    end)

    # Recent outbound events
    [
      {"api.example.com", "/users", "GET", 200, 45.2},
      {"api.example.com", "/posts", "POST", 201, 120.5},
      {"cdn.example.com", "/images/*", "GET", 200, 3.2},
      {"api.example.com", "/search", "GET", 500, 2500.0},
      {"auth.example.com", "/login", "POST", 401, 3.2},
      {"api.example.com", "/users", "GET", 200, 18.3},
    ]
    |> Enum.with_index()
    |> Enum.each(fn {{host, path, method, status, ms}, i} ->
      ts = now - (i + 1) * 10_000
      event = %Event{
        source: :finch, direction: :outbound, method: method, host: host,
        path: path, full_url: "https://#{host}#{path}", status: status,
        status_class: Event.classify_status(status), duration_ms: ms,
        consumer: nil, timestamp: ts, dedup_key: {host, path, method, ts}
      }
      :ets.insert(:monitorex_outbound_recent, {ts, event})
    end)

    # Recent inbound events
    [
      {"GET", "/api/users", "myapp-web", 200, 4.2},
      {"POST", "/api/users", "myapp-web", 201, 45.1},
      {"GET", "/api/search", "myapp-web", 500, 250.0},
      {"GET", "/api/users", "myapp-worker", 200, 2.1},
    ]
    |> Enum.with_index()
    |> Enum.each(fn {{method, path, consumer, status, ms}, i} ->
      ts = now - (i + 1) * 10_000
      event = %Event{
        source: :phoenix, direction: :inbound, method: method, host: "localhost",
        path: path, full_url: "http://localhost#{path}", status: status,
        status_class: Event.classify_status(status), duration_ms: ms,
        consumer: consumer, timestamp: ts, dedup_key: {:inbound, method, path, ts}
      }
      :ets.insert(:monitorex_inbound_recent, {ts, event})
    end)
  end
end

# ── Cache assets (required before endpoint start) ──
_ = Monitorex.Assets.css_hash()
_ = Monitorex.Assets.js_hash()

# ── Start endpoint ──
port = 12_000 + rem(System.unique_integer([:positive]), 10_000)
config = [
  server: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  secret_key_base: Base.encode64(:crypto.strong_rand_bytes(32)),
  debug_errors: false,
  check_origin: false,
]
{:ok, endpoint_pid} = Monitorex.SmokeEndpoint.start_link(config)

# Cleanup function
cleanup = fn ->
  Process.exit(endpoint_pid, :normal)
  Process.sleep(100)
  [:monitorex_outbound_hosts, :monitorex_outbound_endpoints, :monitorex_outbound_recent,
   :monitorex_outbound_duration_samples, :monitorex_inbound_routes, :monitorex_inbound_consumers,
   :monitorex_inbound_recent, :monitorex_inbound_duration_samples, :monitorex_slow_outbound,
   :monitorex_slow_inbound, :monitorex_dedup]
  |> Enum.each(fn t -> try do :ets.delete(t) rescue _ -> :ok end end)
end

# ── Seed data ──
Monitorex.SmokeSeeder.seed()

# ── Verify server is up ──
{:ok, 200, _, body} = :hackney.get("http://127.0.0.1:#{port}/monitorex/health", [], "", with_body: true)
{:ok, health} = Jason.decode(body)
if health["status"] == nil, do: raise "Health check failed: server not responding"

# ── Test runner ──
defmodule SmokeTest do
  def run(label, fun) do
    try do
      result = fun.()
      case result do
        {:ok, detail} ->
          IO.puts("  \e[32m\u2713\e[0m #{label} #{detail}")
          :ok
        {:skip, reason} ->
          IO.puts("  \e[33m-\e[0m #{label} (skipped: #{reason})")
          :skip
        {:fail, reason} ->
          IO.puts("  \e[31m\u2717\e[0m #{label} \u2014 #{reason}")
          :fail
      end
    rescue
      e ->
        IO.puts("  \e[31m\u2717\e[0m #{label} \u2014 #{inspect(e)}")
        :fail
    end
  end
end

base = "http://127.0.0.1:#{port}"

IO.puts("\n=== Monitorex Smoke Test ===\n")
IO.puts("Server: #{base}\n")

# ── Route definitions ──
# Every route the library exposes. Parameterized routes are expanded.
# When new routes are added to http_dashboard, add entries here.

routes = [
  # ── Standalone routes ──
  {"GET",  "/monitorex/health",                      false},

  # ── Export routes ──
  {"GET",  "/export/outbound_overview/csv",          false},
  {"GET",  "/export/outbound_overview/json",         false},
  {"GET",  "/export/outbound_recent/csv",            false},
  {"GET",  "/export/outbound_recent/json",           false},
  {"GET",  "/export/inbound_overview/csv",           false},
  {"GET",  "/export/inbound_overview/json",          false},
  {"GET",  "/export/inbound_recent/csv",             false},
  {"GET",  "/export/inbound_recent/json",            false},
  {"GET",  "/export/inbound_consumers/csv",          false},
  {"GET",  "/export/inbound_consumers/json",         false},
  {"GET",  "/export/timeline/csv",                   false},
  {"GET",  "/export/timeline/json",                  false},

  # ── API sub-routes ──
  {"GET",  "/api/hosts",                             false},
  {"GET",  "/api/hosts/api.example.com",             false},
  {"GET",  "/api/routes",                            false},
  {"GET",  "/api/consumers",                         false},
  {"GET",  "/api/events?direction=outbound",         false},
  {"GET",  "/api/events?direction=inbound",          false},
  {"GET",  "/api/metrics?host=api.example.com",       false},
  {"GET",  "/api/health",                            false},

  # ── LiveView pages ──
  {"GET",  "/",                                      true},
  {"GET",  "/outbound_recent",                       true},
  {"GET",  "/inbound",                               true},
  {"GET",  "/inbound_consumers",                     true},
  {"GET",  "/inbound_recent",                        true},
  {"GET",  "/timeline",                              true},
  {"GET",  "/alerts",                                true},

  # ── LiveView parameterized ──
  {"GET",  "/host/api.example.com",                  true},
  {"GET",  "/host/cdn.example.com",                  true},
  # Note: route detail page (/route/:route_key) uses internal LiveView navigation
  # because route keys contain '/' which conflicts with URL path segments.
  # Not testable via direct HTTP GET.
]

IO.puts("Testing #{length(routes)} routes...\n")

results =
  routes
  |> Enum.map(fn {method, path, is_live} ->
    label = "#{method} #{path}"
    SmokeTest.run(label, fn ->
      url = base <> path

      case :hackney.request(
             String.to_atom(String.downcase(method)),
             url, [], "",
             with_body: true, timeout: 10_000, recv_timeout: 10_000
           ) do
        {:ok, status, _hdrs, body} when status in 200..399 ->
          cond do
            byte_size(body) == 0 ->
              {:fail, "#{status} but empty body"}
            not is_live and String.contains?(body, "Internal Server Error") ->
              {:fail, "#{status} but body contains error page"}
            true ->
              {:ok, "#{status} (#{byte_size(body)}b)"}
          end

        {:ok, status, _hdrs, _body} ->
          {:fail, "status #{status}"}

        {:error, reason} ->
          {:fail, "connection error: #{inspect(reason)}"}
      end
    end)
  end)

# ── Cleanup ──
cleanup.()

# ── Report ──
passed   = Enum.count(results, &(&1 == :ok))
skipped  = Enum.count(results, &(&1 == :skip))
failed   = Enum.count(results, &(&1 == :fail))
total    = length(results)

IO.puts("""

\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
  Total:  #{total} routes tested
  Passed: #{passed}
  Skipped:#{skipped}
  Failed: #{failed}
\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
""")

if failed > 0 do
  IO.puts(:stderr, "SMOKE TEST FAILED: #{failed} route(s) returned errors.")
  System.halt(1)
else
  IO.puts("All routes passed.")
  System.halt(0)
end
