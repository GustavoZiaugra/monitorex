#!/usr/bin/env elixir
# ─────────────────────────────────────────────────────────
# Monitorex — Performance & Load Test (standalone)
# ─────────────────────────────────────────────────────────
# Run: mix run scripts/load_test.exs
#
# Fires 10,000+ synthetic events through the Collector's
# pipeline, monitors ETS sizes, validates ring-buffer caps,
# measures cleanup overhead, and reports memory usage.

Mix.shell().info("⚡ Monitorex Load Test — Standalone")
Mix.shell().info("─" <> String.duplicate("─", 60))

# ── Config ──────────────────────────────────────────────
Application.put_env(:monitorex, :max_recent, 200)
Application.put_env(:monitorex, :max_recent_inbound, 200)
Application.put_env(:monitorex, :cleanup_interval_ms, 500)
Application.put_env(:monitorex, :endpoint_ttl, :timer.minutes(5))
Application.put_env(:monitorex, :sources, [])
Application.put_env(:monitorex, :clients, [])

alias Monitorex.Collector
alias Monitorex.Event

# ── Helpers ─────────────────────────────────────────────

defmodule LoadTest do
  @moduledoc false

  alias Monitorex.Event

  @outbound_hosts ~w(api.example.com api.other.com cdn.static.com auth.service.com
                     payments.gateway.com search.api.com upload.service.com
                     analytics.tracker.com notifications.push.com webhooks.out.com)
  @inbound_routes  ~w(/api/v1/users /api/v1/orders /api/v1/products /health
                      /api/v1/auth/login /api/v1/auth/refresh /api/v1/webhooks
                      /api/v1/search /api/v1/notifications /api/v1/upload)
  @statuses [200, 200, 200, 200, 200, 201, 204, 301, 400, 401, 403, 404, 500, 502, 503]
  @methods ~w(GET POST PUT DELETE PATCH)
  @endpoints_per_host ~w(/api/users /api/orders /api/products /api/search
                         /api/notifications /v1/data /v2/resource /health
                         /auth/login /auth/logout)

  def random_outbound do
    host = Enum.random(@outbound_hosts)
    path = Enum.random(@endpoints_per_host)
    status = Enum.random(@statuses)
    %Event{
      source: :tesla, direction: :outbound, method: "GET",
      host: host, path: path,
      full_url: "https://#{host}#{path}",
      status: status, status_class: Event.classify_status(status),
      duration_ms: :rand.uniform(5000) + :rand.uniform(200),
      timestamp: System.system_time(:second)
    }
  end

  def random_inbound do
    route = Enum.random(@inbound_routes)
    method = Enum.random(@methods)
    status = Enum.random(@statuses)
    %Event{
      source: :phoenix, direction: :inbound, method: method,
      host: "app.example.com", path: route,
      full_url: "https://app.example.com#{route}",
      status: status, status_class: Event.classify_status(status),
      duration_ms: :rand.uniform(2000) + :rand.uniform(50),
      consumer: Enum.random([nil, "user-service", "order-service", "web-app", "mobile-api"]),
      timestamp: System.system_time(:second)
    }
  end

  def make_single_host do
    %Event{
      source: :tesla, direction: :outbound, method: "GET",
      host: "ring-test.com", path: "/api/data",
      full_url: "https://ring-test.com/api/data",
      status: 200, status_class: :success, duration_ms: 50.0,
      timestamp: System.system_time(:second)
    }
  end

  def make_card_event(i) do
    host = "host-#{String.pad_leading(Integer.to_string(i), 5, "0")}.example.com"
    %Event{
      source: :tesla, direction: :outbound, method: "GET",
      host: host, path: "/api/data",
      full_url: "https://#{host}/api/data",
      status: 200, status_class: :success,
      duration_ms: :rand.uniform(100) * 1.0,
      timestamp: System.system_time(:second)
    }
  end

  def sample_ets do
    tables = ~w(monitorex_outbound_hosts monitorex_outbound_endpoints
                monitorex_outbound_recent monitorex_outbound_duration_samples
                monitorex_inbound_routes monitorex_inbound_consumers
                monitorex_inbound_recent monitorex_inbound_duration_samples)a
    Map.new(tables, fn table ->
      size = case :ets.info(table, :size) do; n when is_integer(n) -> n; _ -> 0; end
      memory = case :ets.info(table, :memory) do; n when is_integer(n) -> n; _ -> 0; end
      {table, %{size: size, memory: memory}}
    end)
  end

  def sample_memory do
    mem = :erlang.memory()
    %{total: mem[:total], processes: mem[:processes], system: mem[:system],
      ets: mem[:ets], binary: mem[:binary], code: mem[:code]}
  end

  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB" 
  def format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def format_duration(ms) when is_integer(ms), do: format_duration(ms / 1)
  def format_duration(ms) when ms < 1000, do: "#{Float.round(ms, 1)} ms"
  def format_duration(ms), do: "#{Float.round(ms / 1000, 2)} s"
end

defmodule EtsCleanup do
  @tables ~w(monitorex_outbound_hosts monitorex_outbound_endpoints
             monitorex_outbound_recent monitorex_outbound_duration_samples
             monitorex_inbound_routes monitorex_inbound_consumers
             monitorex_inbound_recent monitorex_inbound_duration_samples
             monitorex_dedup)a

  def clean! do
    Enum.each(@tables, fn table ->
      try do; :ets.delete(table); rescue; _ -> :ok; end
    end)
  end
end

# ═══════════════════════════════════════════════════════
# Scenario 1: Burst Throughput (Outbound Only)
# ═══════════════════════════════════════════════════════

IO.puts("\n── Scenario 1: Burst Throughput (Outbound Only) ──")
EtsCleanup.clean!()

{:ok, burst_collector} = GenServer.start_link(Collector, [], name: :s1_burst)

n_burst = 10_000
IO.write("  Generating #{n_burst} outbound events... ")
events = for _ <- 1..n_burst, do: LoadTest.random_outbound()
IO.puts("done (#{length(events)} events)")

IO.puts("  Sending events...")
ts_start = System.monotonic_time()
Enum.reduce(events, 0, fn event, count ->
  Collector.handle_event(event, :s1_burst)
  count = count + 1
  if rem(count, 1000) == 0 do
    ets = LoadTest.sample_ets()
    IO.write("\r    #{count}/#{n_burst} | recent=#{ets[:monitorex_outbound_recent].size} hosts=#{ets[:monitorex_outbound_hosts].size}")
  end
  count
end)
ts_end = System.monotonic_time()
burst_duration_ms = System.convert_time_unit(ts_end - ts_start, :native, :millisecond)
burst_rate = n_burst / (burst_duration_ms / 1000)
IO.puts("\r    #{n_burst}/#{n_burst} sent in #{LoadTest.format_duration(burst_duration_ms)}")
IO.puts("    Throughput: #{Float.round(burst_rate, 0)} events/sec")

IO.write("  Waiting for cleanup cycle... ")
Process.sleep(1500)
IO.puts("done")

ets1 = LoadTest.sample_ets()
IO.puts("\n  ── ETS table sizes after cleanup ──")
IO.puts("    outbound_hosts:         #{ets1[:monitorex_outbound_hosts].size}")
IO.puts("    outbound_endpoints:     #{ets1[:monitorex_outbound_endpoints].size}")
IO.puts("    outbound_recent:        #{ets1[:monitorex_outbound_recent].size}  (max_recent=200)")
IO.puts("    outbound_duration_samp: #{ets1[:monitorex_outbound_duration_samples].size}")
IO.puts("    inbound_routes:         #{ets1[:monitorex_inbound_routes].size}")
IO.puts("    inbound_consumers:      #{ets1[:monitorex_inbound_consumers].size}")

# ═══════════════════════════════════════════════════════
# Scenario 2: Ring Buffer Capping
# ═══════════════════════════════════════════════════════

IO.puts("\n── Scenario 2: Ring Buffer Capping ──")
Application.put_env(:monitorex, :max_recent, 100)
Application.put_env(:monitorex, :max_recent_inbound, 100)
EtsCleanup.clean!()

{:ok, ring_collector} = GenServer.start_link(Collector, [], name: :s2_ring)

IO.write("  Sending 500 events to same host... ")
single_host = LoadTest.make_single_host()
for _ <- 1..500, do: Collector.handle_event(single_host, :s2_ring)
Process.sleep(1000)

ring_recent = :ets.info(:monitorex_outbound_recent, :size) || 0
IO.puts("done")
IO.puts("  outbound_recent size: #{ring_recent} (expected ≤ 100)")
ring_pass = ring_recent <= 100
IO.puts("  Test: #{if ring_pass, do: "✅ PASS", else: "❌ FAIL"}")

# ═══════════════════════════════════════════════════════
# Scenario 3: Mixed Inbound/Outbound Load
# ═══════════════════════════════════════════════════════

IO.puts("\n── Scenario 3: Mixed Inbound/Outbound Load ──")
Application.put_env(:monitorex, :max_recent, 500)
Application.put_env(:monitorex, :max_recent_inbound, 500)
EtsCleanup.clean!()

{:ok, mixed_collector} = GenServer.start_link(Collector, [], name: :s3_mixed)

n_mixed = 5_000
IO.write("  Generating #{n_mixed} mixed events... ")
mixed_events = for _ <- 1..n_mixed, do:
  if :rand.uniform(2) == 1, do: LoadTest.random_outbound(), else: LoadTest.random_inbound()
IO.puts("done")

ts_s3 = System.monotonic_time()
Enum.each(mixed_events, &Collector.handle_event(&1, :s3_mixed))
te_s3 = System.monotonic_time()
s3_ms = System.convert_time_unit(te_s3 - ts_s3, :native, :millisecond)
s3_rate = n_mixed / (s3_ms / 1000)
IO.puts("  Sent #{n_mixed} events in #{LoadTest.format_duration(s3_ms)} (#{Float.round(s3_rate, 0)}/sec)")

Process.sleep(1000)

ets3 = LoadTest.sample_ets()
IO.puts("\n  ── ETS table sizes ──")
IO.puts("    outbound_hosts:         #{ets3[:monitorex_outbound_hosts].size}")
IO.puts("    outbound_recent:        #{ets3[:monitorex_outbound_recent].size}  (max=500)")
IO.puts("    inbound_routes:         #{ets3[:monitorex_inbound_routes].size}")
IO.puts("    inbound_consumers:      #{ets3[:monitorex_inbound_consumers].size}")
IO.puts("    inbound_recent:         #{ets3[:monitorex_inbound_recent].size}  (max=500)")

# ═══════════════════════════════════════════════════════
# Scenario 4: High Cardinality (10,000 unique hosts)
# ═══════════════════════════════════════════════════════

IO.puts("\n── Scenario 4: High Cardinality (10,000 unique hosts) ──")
EtsCleanup.clean!()

{:ok, card_collector} = GenServer.start_link(Collector, [], name: :s4_card)

n_card = 10_000
IO.write("  Creating #{n_card} events with 10k unique hosts... ")
card_events = for i <- 1..n_card, do: LoadTest.make_card_event(i)
IO.puts("done")

IO.write("  Sending... ")
ts_c = System.monotonic_time()
Enum.each(card_events, &Collector.handle_event(&1, :s4_card))
te_c = System.monotonic_time()
c_ms = System.convert_time_unit(te_c - ts_c, :native, :millisecond)
c_rate = n_card / (c_ms / 1000)
IO.puts("done in #{LoadTest.format_duration(c_ms)} (#{Float.round(c_rate, 0)}/sec)")
Process.sleep(1200)

ets4 = LoadTest.sample_ets()
mem4 = LoadTest.sample_memory()

IO.puts("\n  ── ETS table sizes (10k unique hosts) ──")
IO.puts("    outbound_hosts:         #{ets4[:monitorex_outbound_hosts].size}")
IO.puts("    outbound_endpoints:     #{ets4[:monitorex_outbound_endpoints].size}")
IO.puts("    outbound_recent:        #{ets4[:monitorex_outbound_recent].size}  (max=500)")
IO.puts("\n  ── BEAM Memory ──")
IO.puts("    Total:  #{LoadTest.format_bytes(mem4.total)}")
IO.puts("    ETS:    #{LoadTest.format_bytes(mem4.ets)}")
IO.puts("    System: #{LoadTest.format_bytes(mem4.system)}")
IO.puts("    Binary: #{LoadTest.format_bytes(mem4.binary)}")

# ── Per-host aggregate size ──
host_mem_words = :ets.info(:monitorex_outbound_hosts, :memory) || 0
recent_mem_words = :ets.info(:monitorex_outbound_recent, :memory) || 0
IO.puts("\n── Memory Breakdown ──")
IO.puts("    outbound_hosts:  #{LoadTest.format_bytes(host_mem_words * 8)} (#{host_mem_words} words)")
IO.puts("    → per host:      #{LoadTest.format_bytes(host_mem_words * 8 / n_card)}")
IO.puts("    outbound_recent: #{LoadTest.format_bytes(recent_mem_words * 8)} (#{recent_mem_words} words)")
IO.puts("    → per event:     #{LoadTest.format_bytes(recent_mem_words * 8 / 500)}")

# ═══════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════

IO.puts("\n" <> String.duplicate("─", 60))
IO.puts("📊 Load Test Summary")
IO.puts(String.duplicate("─", 60))
IO.puts("")
IO.puts("  Scenario 1 — Burst (outbound):     #{Float.round(burst_rate, 0)} events/sec — #{n_burst} events")
IO.puts("  Scenario 3 — Mixed in/out:         #{Float.round(s3_rate, 0)} events/sec — #{n_mixed} events")
IO.puts("  Scenario 4 — High cardinality:     #{Float.round(c_rate, 0)} events/sec — #{n_card} unique hosts")
IO.puts("")
IO.puts("  Ring buffer capping:               #{if ring_pass, do: "✅ PASS", else: "❌ FAIL"}")
IO.puts("")
IO.puts("  ETS memory at #{n_card} unique hosts:")
IO.puts("    ~#{LoadTest.format_bytes(host_mem_words * 8)} for host aggregates (#{n_card} entries)")
IO.puts("    ~#{LoadTest.format_bytes(recent_mem_words * 8)} for recent buffer (500 entries)")
IO.puts("")

# Cleanup
Enum.each([:s1_burst, :s2_ring, :s3_mixed, :s4_card], fn name ->
  try do
    pid = Process.whereis(name)
    if pid, do: :sys.terminate(pid, :normal)
  rescue
    _ -> :ok
  end
end)

Mix.shell().info("✅ Load test complete")
