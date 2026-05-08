alias Monitorex.Event

# Create ETS tables
tables = [
  :monitorex_outbound_hosts, :monitorex_outbound_endpoints,
  :monitorex_outbound_recent, :monitorex_outbound_duration_samples,
  :monitorex_inbound_routes, :monitorex_inbound_consumers,
  :monitorex_inbound_recent, :monitorex_inbound_duration_samples
]
Enum.each(tables, fn name ->
  opts = cond do
    name in [:monitorex_outbound_recent, :monitorex_inbound_recent] -> [:public, :named_table, :ordered_set, read_concurrency: true]
    name in [:monitorex_outbound_duration_samples, :monitorex_inbound_duration_samples] -> [:public, :named_table, :bag, read_concurrency: true]
    true -> [:public, :named_table, :set, read_concurrency: true]
  end
  try do :ets.new(name, opts) rescue _ -> :ok end
end)

# Outbound hosts
hosts = [
  {"api.example.com", 342, 12, 15_200.0, 8_500_000, "Finch"},
  {"cdn.example.com", 1_891, 3, 48_500.0, 9_200_000, "Tesla"},
  {"auth.example.com", 156, 8, 6_800.0, 7_800_000, "Finch"},
  {"payments.example.com", 89, 15, 12_400.0, 7_500_000, "Tesla"},
  {"logs.example.com", 45, 0, 1_200.0, 9_500_000, "Finch"},
]
Enum.each(hosts, fn {h, req, err, dur, seen, client} ->
  :ets.insert(:monitorex_outbound_hosts, {h, %{requests: req, errors: err, total_duration: dur, last_seen: seen, client: client}})
end)

# Endpoints per host
endpoints = %{
  "api.example.com" => [{"/users", 120, 4, 3_600.0}, {"/posts", 85, 2, 2_400.0}, {"/comments", 62, 3, 1_800.0}, {"/search", 45, 2, 4_200.0}, {"/upload", 30, 1, 3_200.0}],
  "cdn.example.com" => [{"/images/*", 1_200, 1, 28_000.0}, {"/assets/*", 450, 1, 14_000.0}, {"/videos/*", 241, 1, 6_500.0}],
  "auth.example.com" => [{"/login", 60, 2, 2_800.0}, {"/token/refresh", 50, 3, 2_200.0}, {"/logout", 30, 1, 1_000.0}, {"/verify", 16, 2, 800.0}],
  "payments.example.com" => [{"/charge", 30, 8, 5_200.0}, {"/refund", 25, 3, 3_600.0}, {"/subscription", 20, 2, 2_200.0}, {"/invoice", 14, 2, 1_400.0}],
  "logs.example.com" => [{"/ingest", 30, 0, 800.0}, {"/search", 15, 0, 400.0}],
}
Enum.each(endpoints, fn {host, eps} ->
  Enum.each(eps, fn {path, req, err, dur} ->
    :ets.insert(:monitorex_outbound_endpoints, {{host, path}, %{requests: req, errors: err, total_duration: dur, last_seen: System.system_time(:millisecond)}})
  end)
end)

# Recent events
recent = [
  {"api.example.com", "/users", "GET", 200, 45.2, 2_000_000},
  {"api.example.com", "/users", "GET", 200, 12.8, 1_950_000},
  {"api.example.com", "/posts", "POST", 201, 120.5, 1_900_000},
  {"cdn.example.com", "/images/*", "GET", 200, 3.2, 1_850_000},
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
  {"api.example.com", "/search", "GET", 404, 1.5, 900_000},
  {"cdn.example.com", "/assets/app.js", "GET", 200, 1.8, 800_000},
]
now = System.system_time(:millisecond)
Enum.each(recent, fn {host, path, method, status, dur, ago} ->
  ts = now - ago
  event = %Event{source: :demo, direction: :outbound, method: method, host: host, path: path, full_url: "https://#{host}#{path}", status: status, status_class: Event.classify_status(status), duration_ms: dur, consumer: nil, error: if(status >= 500, do: "HTTP #{status}"), timestamp: ts, dedup_key: {host, path, method, ts}}
  :ets.insert(:monitorex_outbound_recent, {ts, event})
  :ets.insert(:monitorex_outbound_duration_samples, {host, dur})
end)

# Inbound routes
routes = [
  {"GET:/api/users", 345, 8, 12_400.0, 8_000_000},
  {"POST:/api/users", 120, 5, 18_500.0, 7_800_000},
  {"GET:/api/posts", 280, 4, 9_800.0, 8_200_000},
  {"POST:/api/posts", 95, 2, 15_200.0, 7_500_000},
  {"GET:/api/search", 180, 12, 25_000.0, 7_900_000},
]
Enum.each(routes, fn {key, req, err, dur, seen} ->
  :ets.insert(:monitorex_inbound_routes, {key, %{requests: req, errors: err, total_duration: dur, last_seen: seen}})
end)

# Inbound consumers
consumers = [
  {"myapp-web", 450, 10, 18_000.0, 8_100_000},
  {"myapp-worker", 320, 8, 42_000.0, 7_900_000},
  {"myapp-cron", 85, 2, 3_400.0, 7_000_000},
  {"partner-integration", 120, 15, 28_000.0, 7_800_000},
]
Enum.each(consumers, fn {name, req, err, dur, seen} ->
  :ets.insert(:monitorex_inbound_consumers, {name, %{requests: req, errors: err, total_duration: dur, last_seen: seen}})
end)

IO.puts("Demo data seeded!")
