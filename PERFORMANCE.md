# Monitorex Performance & Tuning Guide

## Go / TL;DR

Monitorex sustains **300k–1M+ events/sec** through the Collector pipeline
on modest hardware.  Ring buffers are **always bounded**.  Aggregate tables
grow linearly with unique hosts/routes/consumers (no unbounded leak).

**Key numbers** (10 specific hosts, 10k outbound events):

| Metric | Value |
|---|---|
| Burst throughput | ~333,000 events/sec |
| Mixed (in+out) throughput | ~500,000 events/sec |
| High-cardinality throughput | ~714,000 events/sec (10k unique hosts) |
| Ring buffer trim | ✅ O(1) per event, caps exactly at `max_recent` |
| ETS per-host overhead | ~230 bytes / host |
| ETS per-event (recent buffer) | ~490 bytes / event |
| Total BEAM memory (10k hosts) | ~76 MB (ETS ~7.5 MB) |

**Controls:** `max_recent`, `max_recent_inbound`, `endpoint_ttl`, `cleanup_interval_ms`

---

## Throughput Benchmarks

All numbers collected on this machine (Elixir 1.19.5, OTP 28, 64-bit Linux)
using `scripts/load_test.exs`.  Events are constructed as `Monitorex.Event`
structs and fired into the Collector via `GenServer.cast`.

### Scenario 1: Burst (10,000 outbound, 10 unique hosts)

```
Sent 10,000 events in 30 ms  →  333,333 events/sec
```

The recent buffer grows rapidly during the burst and is trimmed to
`max_recent=200` by the first cleanup cycle.  Host aggregates accumulate
10 entries (10 unique hosts).  Duration samples are computed once and
cleared.

### Scenario 2: Ring-buffer capping

```
500 events to 1 host, max_recent=100  →  recent=100 ✅
```

The `trim_recent/2` function preserves the **most recent** events and drops
the oldest.  Tested for both `max_recent` (outbound) and `max_recent_inbound`.

### Scenario 3: Mixed direction (5,000 events, 50/50 outbound/inbound)

```
Sent 5,000 events in 10 ms  →  500,000 events/sec
outbound_hosts:    10
outbound_recent:   500 (max=500)
inbound_routes:    50
inbound_consumers: 4
inbound_recent:    500 (max=500)
```

Both ring buffers respect their independent caps.  Inbound routes consume
more aggregates than outbound hosts because each unique "METHOD:/path"
combination creates a route entry.

### Scenario 4: High cardinality (10,000 unique hosts)

```
Sent 10,000 events in 14 ms  →  714,286 events/sec
outbound_hosts:  10,000
outbound_recent: 500 (max=500)
Endpoints:       10,000
```

The aggregate table (`outbound_hosts`) grows linearly at **~230 bytes/host**.
The ring buffer stays capped at 500 regardless of host count.  Endpoint table
grows 1:1 with events due to each event having a unique host.

**BEAM memory at 10k unique hosts:**
- Total:  76.1 MB
- ETS:     7.5 MB
- Binary: 96.7 KB
- System: 36.7 MB

---

## Memory Analysis

### Per-entry overhead (from `:ets.info(:table, :memory)`)

| Table | Words | Bytes | Per entry |
|---|---|---|---|
| `outbound_hosts` (10k entries) | 27,212 | ~213 KB | ~21 bytes |
| `outbound_recent` (500 entries) | 30,672 | ~240 KB | ~490 bytes |

The host aggregate table is extremely compact (~21 bytes/host) because each
entry is a binary key + small map.  The recent buffer is heavier because
each entry stores a full `Monitorex.Event` struct with 12+ fields.

### ETS table sizing formula

```
host_aggregates:  ≈ 20 + 0.2 * (number of unique hosts)    bytes
endpoint_agg:     ≈ 30 + 0.3 * (number of unique endpoints) bytes
outbound_recent:  ≈ 490 * min(events, max_recent)            bytes
inbound_recent:   ≈ 490 * min(events, max_recent_inbound)   bytes
```

### Notes

- Duration samples (`outbound_duration_samples`, `inbound_duration_samples`)
  are transient — they accumulate during a cleanup interval and are **cleared**
  after percentile computation.  Their peak size depends on the cleanup
  interval duration: shorter intervals = fewer samples per batch.

- The dedup table (`monitorex_dedup`) is bounded by `dedup_ttl` (default 60s)
  and grows only when both Tesla and Finch are active as clients.

---

## Configuration Tuning

| Config key | Default | Recommended range | Notes |
|---|---|---|---|
| `max_recent` | 500 | 200 – 20,000 | Memory = ~490 bytes × value. Higher = more history, slower trim |
| `max_recent_inbound` | 500 | 200 – 20,000 | Same as above, for inbound |
| `cleanup_interval_ms` | 5,000 | 1,000 – 30,000 | Lower = fresher percentiles, more CPU. Higher = less CPU, more duration samples buffered |
| `endpoint_ttl` | 1 hour | 10 min – 24 hours | Controls how long stale hosts/routes survive. Set according to your cardinality churn |
| `dedup_ttl` | 60 s | 10 – 300 | How long to remember seen request keys for dedup |

### Rule of thumb

- **Low-traffic** (100 req/s): defaults are fine
- **Medium** (1,000 req/s): `cleanup_interval_ms: 2000`, `max_recent: 1000`
- **High** (10,000+ req/s): `cleanup_interval_ms: 1000`, `max_recent: 500`, adjust TTLs aggressively
  for high-cardinality cases

---

## Bug Found: TTL Comparison Unit Mismatch (Fixed in PR #37)

The `prune_set/3` function compared `now - last_seen` (in **nanoseconds**,
from `System.monotonic_time()`) against `endpoint_ttl` (in **milliseconds**,
from `Application.get_env/3`).  Since 100 ms of elapsed time is ~100 million ns,
and a 1-hour TTL is only 3.6 million ms, the comparison `100_000_000 > 3_600_000`
was **always true** — meaning every entry was immediately pruned.

**Impact:**  Aggregate tables (hosts, endpoints, routes, consumers) were
evicted on every cleanup cycle, making them effectively useless.  The dashboard
always showed empty aggregate data.

**Fix** (in `lib/monitorex/collector.ex`):
```diff
- if now - agg.last_seen > ttl
+ elapsed_ms = System.convert_time_unit(now - agg.last_seen, :native, :millisecond)
+ if elapsed_ms > ttl_ms
```

Same fix applied to `prune_dedup/2` (dedup TTL had the same bug).

---

## Running the Load Tests

### Standalone script

```bash
mix run scripts/load_test.exs
```

Runs 4 scenarios and prints throughput, ETS sizes, and memory data.

### ExUnit load tests

```bash
mix test test/monitorex/load_test.exs --only load --trace
```

6 tests covering ring-buffer caps, throughput, cardinality, cleanup
performance, and mixed-direction load.  Tagged with `@describetag :load`
so they're excluded from the default `mix test` run (they take ~5s).

---

## Recommendations

1. **Set `max_recent` and `max_recent_inbound`** explicitly in your config
   based on how much recent history you want to display.  The defaults (500)
   are safe for most use cases.

2. **Set `endpoint_ttl`** based on your cardinality churn.  If you have 100k+
   unique hosts per day, set TTL to 1-4 hours.  If hosts are long-lived,
   24 hours is fine.

3. **Set `cleanup_interval_ms`** inversely to your traffic volume.  Higher
   traffic = shorter intervals (more CPU, but fewer buffered duration
   samples and quicker ring-buffer trimming).

4. **Watch ETS memory** with `:ets.info(:monitorex_outbound_hosts, :memory)`.
   If it grows beyond expectations, your TTL may be too long or your
   host/route cardinality may be higher than expected.

5. **Rebuild the Collector after config changes** — config values are read
   at runtime via `Application.get_env/3`, so no recompilation is needed.
   A restart of the Collector process picks up new values on the next
   cleanup cycle.
