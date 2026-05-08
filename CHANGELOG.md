# Changelog

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
