# Changelog

## Unreleased

## 0.8.0 (2026-08-01)

### Breaking

- **Dashboard is mountable at any path prefix** — the mount contract was broken for any non-root scope (#107, #119). Nav links, asset hrefs, export links and the LiveView socket path are now derived from the mount point (`conn.script_name` + router scope). The previous root-only constraint is removed; `http_dashboard/1` gains a `:socket_path` option. Rebuild asset/nav links as needed if you relied on the old root-absolute hrefs (#119, #125, #132).
- **LiveView client is now shipped** — the dashboard previously rendered without any Phoenix client (no `LiveSocket`), so `phx-click` bindings were inert and the UI never updated. `priv/static/app.js` now bundles the LiveSocket client; the layout emits a CSRF token meta and the host socket path (#101, #119).

### Added

- **Igniter installer** — `mix igniter.install monitorex` sets up the dependency, router mount (`scope "/monitoring"` + dedicated pipeline without `protect_from_forgery`), source detection (tesla/finch/req), Tesla-on-Finch dedup, and `api_path: false` (#114, #122).
- **Outbound nav section** — the sidebar now groups Outbound (Overview, Recent), Inbound, Analysis (Timeline, Alerts), and Cluster symmetrically (#112, #124).
- **`http_dashboard` `:socket_path` option** — override the host LiveView socket path (default `"/live"`).
- **Runtime warning when `:req` source is misconfigured** — modern Req (0.5+) doesn't emit `[:req, :request, :pipeline, :stop]`; monitorex now warns at boot when `:req` is enabled without `req_telemetry`, and documents the `:finch` alternative (#129, #134).

### Fixed

- **Host apps could not boot** — `:hackney` was in `extra_applications` despite being `optional: true`, forcing every host to include hackney (#102, #116).
- **AlertHistory crashed on every cleanup** — the cleanup handler called the public API from inside the GenServer process (`process attempted to call itself`), restart-looping and discarding alert state (#108, #117).
- **LiveView interactive layer restored** — `phx-target={@myself}` was missing on 30+ bindings across the timeline, outbound/inbound recent, and shared `Core` components; `push_navigate` was called with bare query strings; `find_selected` only searched the visible page; the timeline search box emitted an untargeted `phx-keyup` (#103, #104, #110, #111, #120).
- **Export links were root-absolute** — `export_button` hrefs ignored the mount prefix, so CSV/JSON exports broke under a scope mount (#127, #132).
- **Outbound Overview node selector crashed the LiveView** — `Core.node_selector` emitted a `select_node` event with no handler; the dropdown now filters the host table (#128, #133).
- **Finch telemetry dropped request/response headers and bodies** — the Req adapter returns the response as a `{status, headers, body, trailers}` tuple; headers/bodies (iodata) are now extracted, redacted and stored when body capture is enabled (#126).
- **Demo seeded aggregates with wrong timestamps** — `scripts/demo.exs` seeded `last_seen` in milliseconds while the storage layer prunes in microseconds, so every host/route/consumer was evicted immediately; the demo now renders full data (#136, #137).
- **`immutable` cache on unversioned asset URLs** — assets are now versioned (`app.css?v=<hash>`) so browsers don't pin stale bundles for a year (#109, #119).
- **CI flaky tests** — the alerts notifier tests raced the background collector's debounce; the timeline status-filter test matched raw status digits in epoch timestamps; both are stable now (#115, #121, #123).
- **Removed the broken `priv/` demo** — `priv/demo_app.ex`/`demo_router.ex`/`run_demo.exs` referenced nonexistent modules; the working demo is `scripts/demo.exs` (#130, #135).

### Changed

- **CI is enforced** — credo no longer runs with `|| true`, and the `test` job is a required status check on `main` (#115, #121).
- **README screenshots refreshed** — outbound overview, host detail and timeline now show the new nav and live data.
- **Docs** — real installation guide covering path-prefix mounts, `api_path`, CSP, pipeline requirements, Tesla/Finch dedup, body capture and data lifetime (#113, #118).
- **Test hygiene** — `on_exit` cleanup for config leaks in alert-history and alerts tests (#131, #135).

## 0.7.2 (2026-07-28)

### Fixed
- **OTP 29 crash** — `compute_percentiles/1` now guards all ETS operations with `try/rescue` to prevent GenServer termination when the cleanup timer fires during test table resets (#98)
- **Flaky webhook test** — register `on_exit` cleanup immediately after `Application.put_env` so config is cleaned up even on assertion failure (#99)

### Changed
- Dependency bumps: `credo` 1.7.18→1.7.19, `db_connection` 2.10.1→2.10.2, `exqlite` 0.37.0→0.39.0, `floki` 0.38.3→0.38.4 (#98)

## 0.7.1 (2026-07-24)

### Security
- **hackney** `~> 1.18` → `~> 4.5` — fixes CVEs CVE-2026-47075, CVE-2026-47076, CVE-2026-47069, CVE-2026-47071 (#96)
- **phoenix_live_view** `~> 1.1` → `~> 1.2` — latest 1.2.7 with ongoing security support (#96)
- **tailwind** `~> 0.4.1` → `~> 0.5` — latest 0.5.1 (#96)
- Transitive dependency updates: `certifi`, `cowboy`, `cowlib`, `idna`, `parse_trans`, `phoenix`, `plug`, `plug_cowboy`, `websock_adapter` (#96)

## 0.7.0 (2026-06-21)

### Added
- **Support for Elixir 1.20.0 and OTP 29** — CI matrix expanded to include `elixir: '1.20', otp: '29'` (#83)
- **CI smoke test pipeline** — route-level acceptance smoke test hits every dashboard route in CI (#91)
- **AGENTS.md** — test conventions, architecture notes, and tooling commands for contributors (#90)

### Changed
- **Test coverage** increased to 93.51% across all modules (#89)
- **Code quality** — resolved all Credo strict-mode warnings (#88):
  - `String.to_atom/1` → `String.to_existing_atom/1` in `DashboardLive.atomize_keys/1`
  - Replaced `length/1` comparisons with empty-list checks in tests
  - Added `# credo:disable-for-next-line` annotations for intentional runtime atom creation in tests
- Local development tool-versions updated to Elixir 1.20.0-otp-29 and Erlang 29.0

### Fixed
- Elixir 1.20 compatibility: pinned bitstring size variable in `EventHandler.truncate_body/2` with `^max` to satisfy new hard deprecation
- Removed unused `Logger` require in `AlertHistory`
- Removed unreachable nil clauses in `TimelinePage` that Elixir 1.20's compiler now correctly flags

### Security
- Audited and updated dependencies to latest patch/minor versions (#87):
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
