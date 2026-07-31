# Installation Guide

This guide integrates Monitorex into a **real** Phoenix application. The README
Quick Start covers the happy path; this guide covers the constraints that trip
up real apps — where the dashboard can be mounted, the pipeline it needs, the
unauthenticated REST API, body capture, and data lifetime.

> **Read this before integrating.** Nearly all Monitorex integration friction
> comes from five undocumented requirements:

1. The REST API mounts with **no authentication** and defaults to `/api`,
   colliding with most apps' API scope.
2. The asset route returns **403** behind `protect_from_forgery`.
3. Tesla-on-Finch **double-counts** every outbound request without `:clients`.
4. Request/response bodies are **dropped** unless you opt in.
5. All data is **in-memory** by default and silently evicted.

## 1. Add the dependency

Add `monitorex` to your `mix.exs`:

```elixir
def deps do
  [
    {:monitorex, "~> 0.7.0"}
  ]
end
```

If you monitor the `:req` source, Req 0.5.x removed built-in telemetry — you
also need `req_telemetry`:

```elixir
def deps do
  [
    {:monitorex, "~> 0.7.0"},
    {:req_telemetry, "~> 0.1"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## 2. Copy-pasteable setup

The complete "real app" configuration is below. Each block is explained in the
sections that follow.

### `config/config.exs`

```elixir
import Config

config :monitorex,
  # Only the clients you actually use. :phoenix monitors inbound traffic;
  # the rest monitor outbound requests.
  sources: [:tesla, :finch, :req, :phoenix],

  # REQUIRED if Tesla runs on the Finch adapter (very common): Tesla's Finch
  # adapter emits BOTH a Tesla and a Finch telemetry event for the same
  # request. Without this, every outbound request is counted twice.
  clients: [:tesla, :finch],

  # Body capture is OFF by default. Without these, the timeline detail pane
  # shows headers but empty request/response bodies.
  store_request_body: true,
  store_response_body: true,
  max_body_bytes: 10_000,

  # Slow-request tracing retains bodies past this threshold (in ms) even when
  # body storage is disabled.
  slow_request_threshold_ms: 2_000,

  # ETS defaults: 500 recent events per direction. Older events are silently
  # evicted, so deep links like /timeline?selected=1779232233155167 break
  # once the event is evicted.
  max_recent: 500,
  max_recent_inbound: 500

  # Optional: persist across restarts (ETS is the default and is wiped on
  # restart). Requires {:exqlite, "~> 0.29"} in your deps.
  # storage: Monitorex.Storage.SQLite,
  # sqlite_path: "/var/lib/monitorex/data.db"
```

### `lib/my_app_web/router.ex`

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import Monitorex.Router

  # Dashboard pipeline — deliberately NOT your :browser pipeline.
  #
  # 1. NO protect_from_forgery: Plug.CSRFProtection rejects non-XHR GET
  #    requests that serve JavaScript (a 403 on app.js; CSS is unaffected,
  #    which makes this confusing to diagnose).
  # 2. NO CSP plug: Monitorex's scripts carry no nonce, so a strict-dynamic
  #    Content-Security-Policy blocks them. There is no
  #    csp_nonce_assign_key option yet.
  pipeline :monitoring do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
  end

  # Dedicated host mount — the reliable option in the current release.
  # Point monitoring.example.com at this app, then visit
  # https://monitoring.example.com/
  scope "/", host: "monitoring." do
    pipe_through :monitoring

    # api_path: false — the REST API is unauthenticated and would otherwise
    # mount at /api, colliding with your app's API scope.
    http_dashboard api_path: false
  end
end
```

### `mix phx.server`

```bash
mix phx.server
```

Visit `https://monitoring.example.com/` (or `http://localhost:4000/` while
testing locally) to see your dashboard.

## 3. Where it can be mounted

The `http_dashboard` macro emits **scope-relative** routes (`live "/"`,
`get("/dashboard-assets/*path")`, `forward("/api")`), so a path prefix is
supported at the router level:

```elixir
scope "/monitoring" do
  pipe_through :monitoring
  http_dashboard api_path: false
end
```

However, in the current release the bundled layout and asset plug still
**hardcode root-relative URLs** (`/dashboard-assets/app.css`, nav links to `/`,
`/timeline`, …). Until that fix lands (in progress), a prefix mount renders the
dashboard but its assets and navigation point at the root. The reliable option
today is a **dedicated host**:

```elixir
scope "/", host: "monitoring." do
  pipe_through :monitoring
  http_dashboard api_path: false
end
```

Point the `monitoring.` subdomain at your app's endpoint, and the dashboard's
root-relative URLs resolve correctly.

## 4. The REST API: disable it

> **⚠️ Security warning.** Monitorex auto-mounts a JSON REST API **outside**
> `live_session` with **no authentication**. It defaults to `/api` — the path
> most real apps already use for their own API. Anyone who can reach your
> endpoint can read hosts, events, and metrics.

Unless you need it, disable it:

```elixir
http_dashboard api_path: false
```

If you do need it, keep it off the dashboard scope and mount the plug yourself
under your own pipeline and/or a dedicated path:

```elixir
# Keep http_dashboard api_path: false, then forward the API explicitly:
scope "/monitoring/api" do
  pipe_through :api  # your authenticated API pipeline
  forward "/", Monitorex.ApiPlug
end
```

(When `http_dashboard` mounts it itself, `:api_path` is **scope-relative** — the
default `/api` becomes `/monitoring/api` inside `scope "/monitoring"`.)

The API also sends `Access-Control-Allow-Origin: *` on every response and
answers `OPTIONS` preflights, so it is effectively public even if your
dashboard scope is authenticated.

## 5. Pipeline requirements

Two things must be true of the pipeline the dashboard scope runs through:

- **No `protect_from_forgery`.** Phoenix's `:browser` pipeline includes it.
  `Plug.CSRFProtection` rejects any non-XHR GET request that serves a
  JavaScript content type — exactly what the `<script src="/dashboard-assets/app.js">`
  tag is. The result is a 403
  (`Plug.CSRFProtection.InvalidCrossOriginRequestError`) on `app.js` while
  `app.css` loads fine, which looks like a broken asset path.
- **No CSP plug** (if your app enforces a `strict-dynamic` Content-Security-Policy).
  Monitorex serves its script without a nonce and `http_dashboard` has no
  `csp_nonce_assign_key` option yet — Oban.Web's `oban_dashboard/2` has one and
  is the pattern to follow. Until then, keep the dashboard on a pipeline that
  does not apply your CSP headers.

The `:monitoring` pipeline in the example above satisfies both. If you instead
reuse `:browser`, create a dedicated pipeline that mirrors it minus
`protect_from_forgery` and the CSP plug.

## 6. Deduplication (Tesla on Finch)

If you use Tesla on the Finch adapter — Tesla's most common adapter — **both**
`[:tesla, :request, :stop]` and `[:finch, :request, :stop]` fire for the same
request. Without dedup, every outbound request is recorded twice.

This is **required**, not optional, whenever Tesla runs on Finch:

```elixir
config :monitorex, :clients, [:tesla, :finch]
```

The `:clients` list must contain **both** `:tesla` and `:finch` for the dedup
table to be created. Add any other clients you use (e.g. `:req`) as well.

## 7. Body capture and slow-request tracing

`store_request_body` / `store_response_body` default to `false`. Without them,
the timeline detail pane shows request/response **headers** but empty
**bodies** — it looks broken, but Monitorex is just not storing bodies.

```elixir
config :monitorex,
  store_request_body: true,
  store_response_body: true,
  max_body_bytes: 10_000
```

Slow-request tracing is independent: requests exceeding
`:slow_request_threshold_ms` (default `2_000`) capture and retain full bodies
even when body storage is globally disabled. Bodies larger than
`:max_body_bytes` (default `10_000`) are truncated.

Set `:slow_request_threshold_ms` to `nil` or `0` to disable slow tracing.

## 8. Data lifetime

Monitorex defaults to **ETS storage (in-memory)**:

- Everything is lost on BEAM restart. For persistence, enable the SQLite
  backend (add `{:exqlite, "~> 0.29"}` to your deps):

  ```elixir
  config :monitorex, :storage, Monitorex.Storage.SQLite
  config :monitorex, :sqlite_path, "/var/lib/monitorex/data.db"
  ```

- Recent-event buffers hold `:max_recent` (default `500`) events per direction.
  Older events are **silently evicted** during the cleanup cycle — this breaks
  deep links such as `/timeline?selected=<timestamp>` once the event is gone.

## 9. Verify your install

```bash
mix compile
mix phx.server

# Health check (no auth)
curl http://localhost:4000/monitorex/health
```

The health endpoint reports Collector status, ETS table sizes, and total ETS
memory. With `api_path: false` the REST API endpoints are disabled by design.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `app.js` returns 403, `app.css` loads | `protect_from_forgery` in the dashboard pipeline rejects the JS GET | Use a pipeline without `protect_from_forgery` (see §5) |
| Script blocked / CSP violation | `strict-dynamic` CSP; Monitorex scripts have no nonce | Serve the dashboard through a pipeline without your CSP plug (see §5) |
| Outbound counts are 2× | Tesla on Finch adapter without dedup | `config :monitorex, :clients, [:tesla, :finch]` (see §6) |
| Empty bodies in the detail pane | Body capture off by default | `store_request_body: true`, `store_response_body: true` (see §7) |
| `?selected=` deep link shows nothing | Event evicted from the 500-event recent buffer | Raise `:max_recent`, or check before cleanup (see §8) |
| All data gone after restart | ETS (in-memory) is the default backend | Enable the SQLite backend (see §8) |
| `/api` collides with your API scope | REST API defaults to `/api`, unauthenticated | `http_dashboard api_path: false` (see §4) |
