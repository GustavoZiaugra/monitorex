# Changelog

## Unreleased

### Added
- **Support for Elixir 1.20.0 and OTP 29** — CI matrix expanded to include `elixir: '1.20', otp: '29'` (#74)
- Local development tool-versions updated to Elixir 1.20.0-otp-29 and Erlang 29.0

### Fixed
- Elixir 1.20 compatibility: pinned bitstring size variable in `EventHandler.truncate_body/2` with `^max` to satisfy new hard deprecation
- Removed unused `Logger` require in `AlertHistory`
- Removed unreachable nil clauses in `TimelinePage` that Elixir 1.20's compiler now correctly flags

### Changed
- `String.to_atom/1` → `String.to_existing_atom/1` in `DashboardLive.atomize_keys/1` (Credo)
- Replaced `length/1` comparisons with empty-list checks in tests (Credo)
- Added `# credo:disable-for-next-line` annotations for intentional runtime atom creation in tests

### Security
- Audited and updated dependencies to latest patch/minor versions (#85):
  - `phoenix` 1.8.5 → 1.8.7
  - `phoenix_live_view` 1.1.28 → 1.1.31
  - `telemetry` 1.4.1 → 1.4.2
  - `jason` 1.4.4 → 1.4.5
  - `exqlite` 0.36.0 → 0.37.0
  - `ex_doc` 0.40.1 → 0.40.3
  - `floki` 0.38.1 → 0.38.3
  - `req` 0.5.17 → 0.5.18
  - `plug` 1.19.1 → 1.19.2
  - `mint` 1.8.0 → 1.9.0
  - `cowboy` 2.13.0 → 2.14.0
  - `cowlib` 2.16.0 → 2.16.1
  - `elixir_make` 0.9.0 → 0.10.0

## 0.6.0 (2026-05-24)

### Added
- **Alert Center UI** — `/alerts` page with summary cards, firing alerts list, and history table with status badges, acknowledge, and snooze controls (#69)
- **Alert History** — GenServer-backed ETS storage for alert records with ack, snooze, expire, and automatic trim (#69)
- **Native Notifications** — Slack, Discord, and Email notifiers with debounced dispatch via `Monitorex.Notifier` behaviour (#69)
- **Slow Request Tracing** — automatic capture of request/response bodies for requests exceeding `:slow_request_threshold_ms`, stored in separate ETS tables (#70)
- **Persistent Storage Backend** — optional SQLite adapter via `Monitorex.Storage.Backend` behaviour; ETS remains default, zero breaking changes (#71)
- **REST API** — programmatic JSON access to hosts, routes, events, consumers, and metrics with pagination and CORS (#72)
- **CSV/JSON Export** — download any dashboard view as `.csv` or `.json` from the UI (#73)
- **Alert Runtime CRUD** — `add_rule/1`, `remove_rule/1`, `list_rules/0` for dynamic alert configuration at runtime (#69)

### Changed
- ETS table operations now guarded against `:undefined` to prevent crashes when tables are absent during tests or race conditions (#69, #70)
- `exqlite` added as `optional: true` dependency for SQLite backend (#71)
- `:hackney` and `:gen_smtp` added as `optional: true` for native notification dispatch (#69)

### Fixed
- Dialyzer contract for `tag_slow_request/2` corrected to accept `any()` metadata (#70)
- Integration test dedup flow ETS cleanup extended to include slow tables (#70)

## 0.5.1 (2026-05-16)

### Fixed
- Timestamp normalization: event handlers and collector now store `System.system_time(:microsecond)` instead of `System.monotonic_time()` — fixes timestamps showing dates from 1970 and broken timeline time-ago buckets (#66)
- Inbound Consumers page crash (`KeyError :avg_latency`) — compute average latency from `total_duration / requests` (#66)
- Demo seed data: seed 15 inbound recent events so inbound pages aren't empty; use real epoch timestamps for all `last_seen` values (#66)
- Cleanup `format_duration/1` unreachable clause flagged by Dialyzer (#66)

## 0.5.0 (2026-05-13)

### Added
- Configurable max event limits and `Monitorex.memory_usage/0` helper — `:max_endpoints`, `:max_recent`, `:max_recent_inbound`, `:endpoint_ttl` (#57, #60)
- Req HTTP client telemetry handler — capture Req requests via `source: :req` (#55, #58)
- ExDoc documentation with full API reference and Getting Started guide (#56, #59)
- Memory management documentation in README — `:max_endpoints`, ETS pruning, memory_usage/0 (#61)

### Fixed
- Req telemetry handler: Req 0.5.x removed built-in telemetry — now uses `req_telemetry` package events (`[:req, :request, :pipeline, :stop]`) (#55, #63)
- CI flakiness: integration test now restores ETS tables instead of stopping Collector globale (#62)
- hex.pm badges and published docs link in README (#54)

### Changed
- Removed auto-publish workflow — Hex releases now manual only (#53)

## 0.4.0 (2026-05-13)

### Added
- Timeline revamp: time-grouped sections (Just now, 1m ago, etc.), search bar, status/method filters (#51)

### Fixed
- ex_doc availability in all envs for `mix hex.publish` docs task (#50)
- Removed `priv/assets` from package files (directory doesn't exist)

### Changed
- Replaced placeholder screenshots with real dashboard screenshots in README

## 0.3.0 (2026-05-08)

### Added
- Timeline split-pane dashboard (Concept A) — `/timeline` page with vertical event list + request/response inspector
- Header redaction via `HeaderRedactor` — sensitive headers (authorization, set-cookie, x-api-key) auto-masked
- Request/response body capture and display in detail view
- Health check endpoint (`GET /monitorex/health`) with Collector status, queue depths, ETS sizes
- Prometheus metrics exporter (`GET /monitorex/metrics`) — requests, errors, latency, ETS sizes
- Alert webhooks with configurable thresholds (error_rate, host_down, high_latency) and debounced dispatch
- ErrorBoundary LiveComponent for graceful crash recovery
- Error boundary CSS card with retry button

### Changed
- `status_chip_class/2` extracted to `Monitorex.Components.Live.Helpers` (removed duplication across inbound/outbound pages)
- Sort/filter/pagination state persisted in URL query params across all pages
- Responsive layout revamp: sidebar collapse on mobile, card-based table layout below 768px
- ETS prune/cleanup uses `System.convert_time_unit/3` — fixes TTL bug where hosts were always deleted

### Fixed
- TTL bug: `prune_set` compared nanoseconds vs milliseconds, causing all entries to be immediately evicted
- Dedup bug: same nanoseconds-vs-milliseconds confusion in `prune_dedup`
- `Assets.init/1` now ignores opts keyword list (was crashing Phoenix dev mode)
- Assets path now works when mounted under root scope

### Tests
- 355+ tests across all modules
- Integration tests for Tesla, Finch, Phoenix pipeline
- Performance/load tests for Collector throughput and memory usage
- Cluster support with multi-node test infrastructure
- 6 new test suites: application, authentication, event, helpers, layouts, resolver

## 0.2.0 (2026-04-xx)

### Added
- Sortable data tables with URL-persisted sort/filter state across all pages
- Cluster support: multi-node telemetry aggregation with merge strategies
- Responsive mobile layout: collapsible sidebar, card-based responsive tables
- Detail pages for individual hosts and routes
- Inbound overview, consumers, and recent pages
- Filter by status class (2xx/3xx/4xx/5xx) and host
- Pagination component with ellipsis for large datasets
- Auto-refresh every 2 seconds
- Node selector dropdown in cluster mode

## 0.1.0 (2026-04-xx)

### Added
- Core data pipeline: EventHandler, Collector (ETS-based), Storage (read/query layer)
- Outbound HTTP monitoring for Tesla and Finch clients
- Inbound HTTP monitoring for Phoenix endpoints
- URL redaction (sanitize query params)
- Consumer identification from Basic Auth headers
- Dashboard LiveView with Outbound overview page
- Dark theme design system with CSS custom properties
- Phoenix Router macro (`http_dashboard`) for embedding
- Asset serving via `Monitorex.Assets` plug
- Authentication/Authorization hooks with extensible Resolver behaviour
- GitHub Actions CI pipeline (compile, test, credo, dialyzer)
