# Agent Instructions

## Commands

```bash
mix test                                    # 630 tests, ~8s — must pass before commit
mix test test/path/to/file.exs              # single file
mix compile --warnings-as-errors            # strict compilation
mix dialyzer                                # type checking
mix credo                                   # linting (max line 160, max nesting 3)
mix format --check-formatted                # formatter check
```

## Test conventions

**ETS safety:** Any test that creates or touches ETS tables (`:ets.new`, `:ets.insert`, etc.) **must use `async: false`**. ETS named tables are global — async tests will race against each other. Only pure-function tests (no ETS) may use `async: true`.

**Test support:** `test/support/live_component_fixtures.ex` is compiled in `:test` env (see `elixirc_paths` in `mix.exs`). It provides:
- `LiveComponentFixtures.reset_ets_tables/0` — destroy and recreate all 11 standard ETS tables with correct types (`:bag` for `*_duration_samples`, `:ordered_set` for `*_recent` and `*_slow`, `:set` for everything else)
- `LiveComponentFixtures.reset_ets_tables/1` — same, for a custom table list
- `insert_outbound_event/1` / `insert_inbound_event/1` — seed event helpers

Use these instead of inlining ETS setup.

**Mocking:** `meck` (test-only dep) is used to mock `:hackney`, `:gen_smtp_client`, and internal cluster functions. Every test that calls `:meck.new` **must** call `on_exit(fn -> :meck.unload() end)` or `:meck.unload/1` to avoid leaking mocks between tests.

**Config cleanup:** `Application.put_env` must be paired with `on_exit(fn -> Application.delete_env(...) end)` immediately after — not at the bottom of the test body. If an assertion fails mid-test, the env will still be cleaned up.

**GenServer guards:** `Alerts` and `AlertHistory` are GenServers. If your test calls `Alerts.list_rules()`, `Alerts.add_rule()`, etc. in setup, guard with `Process.whereis(Alerts)` — other test files may not have started the GenServer.

**SQLite tests:** `test/monitorex/storage/sqlite_test.exs` starts with `if Code.ensure_loaded?(Exqlite)` — they skip automatically when `exqlite` is not available.

## Architecture

Monitorex is an Elixir Hex **library** that mounts into a host Phoenix app. It is NOT a standalone application.

```
lib/monitorex/
├── collector.ex          # ETS aggregation process, telemetry handler, cleanup cycle
├── event_handler.ex      # telemetry → Event struct conversion, body truncation, slow tagging
├── storage/              # Storage.Backend behaviour + ETS (default) + SQLite (optional)
├── alerts.ex             # threshold evaluation + debounce + notifier dispatch
├── alert_history.ex      # GenServer-backed ETS history store
├── notifiers/            # Slack, Discord, Email notifier modules
├── api.ex                # REST API functions (query hosts, events, metrics)
├── api_plug.ex           # REST API plug (pagination, filtering)
├── exports.ex            # CSV/JSON export functions (Exports.export/2)
├── export_plug.ex        # export request routing plug
├── health.ex             # health check (collector status, ETS sizes, queue depths)
├── prometheus_exporter.ex # Prometheus text-format metrics
├── router.ex             # Phoenix Router macros for mounting
├── components/live/      # 8+ LiveView page modules + helpers
├── url_normalizer.ex     # URL → host/path extraction
├── url_redactor.ex       # URL query redaction
└── consumer_identifier.ex # Phoenix consumer name extraction
```

**Key types:** `Monitorex.Event` struct is the central data type flowing through the pipeline: `telemetry → EventHandler → Event struct → Collector → ETS`.

## Gotchas

- **Webhook alerts:** `fire_webhook/2` strips internal fields (`:notifiers`, `:status`, `:acknowledged_at`, `:snoozed_until`, `:id`) from the alert map before JSON encoding. Adding new tuple-typed fields to the alert map requires the same treatment.
- **Dialyzer:** One intentional ignore: `gen_smtp_client.send_blocking` in `notifiers/email.ex` — the runtime type is wider than the spec.
- **Branch protection:** `main` requires 1 PR approval, conversation resolution, no force push, no direct deletion. Merge only via PR.
- **No CI pipeline:** The README badge references a workflow that does not exist yet. Verify `mix test`, `mix dialyzer`, and `mix compile --warnings-as-errors` locally before merging.
- **Elixir version:** supports `~> 1.15` (backward to OTP 26). Avoid 1.20+-only features.
