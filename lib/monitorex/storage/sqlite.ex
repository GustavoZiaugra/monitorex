if Code.ensure_loaded?(Exqlite.Sqlite3) do
  defmodule Monitorex.Storage.SQLite do
    @moduledoc """
    SQLite-backed implementation of `Monitorex.Storage.Backend`.

    Stores telemetry events in a local SQLite database.  Designed for
    deployments that need durability across node restarts or lower
    in-memory footprint than the ETS backend.

    ## Configuration

        config :monitorex, :storage_backend, Monitorex.Storage.SQLite
        config :monitorex, :sqlite_path, "/var/lib/monitorex/data.db"

    The default path is `:code.priv_dir(:monitorex) <> "/monitorex.db"`.
    """

    @behaviour Monitorex.Storage.Backend

    alias Monitorex.Event

    @default_limit 50

    # ── Connection ──

    defp conn do
      path = Application.get_env(:monitorex, :sqlite_path, default_db_path())

      # Use persistent connection stored in process dictionary to avoid
      # reopening the DB on every call.
      existing = Process.get(:monitorex_sqlite_conn)

      if existing do
        existing
      else
        {:ok, db} = Exqlite.Sqlite3.open(path)
        init_schema(db)
        Process.put(:monitorex_sqlite_conn, db)
        db
      end
    end

    defp default_db_path do
      priv = :code.priv_dir(:monitorex)
      Path.join(to_string(priv), "monitorex.db")
    end

    defp init_schema(db) do
      :ok =
        sql_exec(
          db,
          "CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            direction TEXT NOT NULL,
            host TEXT,
            path TEXT,
            method TEXT,
            status INTEGER,
            status_class TEXT,
            duration_ms REAL,
            request_body TEXT,
            response_body TEXT,
            consumer TEXT,
            slow INTEGER,
            dedup_key TEXT
          );",
          []
        )

      :ok =
        sql_exec(
          db,
          "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);",
          []
        )

      :ok =
        sql_exec(
          db,
          "CREATE INDEX IF NOT EXISTS idx_events_direction ON events(direction);",
          []
        )

      :ok =
        sql_exec(db, "CREATE INDEX IF NOT EXISTS idx_events_host ON events(host);", [])

      :ok =
        sql_exec(
          db,
          "CREATE INDEX IF NOT EXISTS idx_events_status_class ON events(status_class);",
          []
        )

      :ok =
        sql_exec(
          db,
          "CREATE TABLE IF NOT EXISTS aggregates (
            key TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            requests INTEGER DEFAULT 0,
            errors INTEGER DEFAULT 0,
            total_duration REAL DEFAULT 0.0,
            last_seen INTEGER DEFAULT 0
          );",
          []
        )

      :ok
    end

    # ── Write callbacks ──

    @impl true
    def record_event(%Event{} = event) do
      db = conn()

      :ok =
        sql_exec(
          db,
          "INSERT INTO events
           (timestamp, direction, host, path, method, status, status_class,
            duration_ms, request_body, response_body, consumer, slow, dedup_key)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13);",
          [
            event.timestamp || System.system_time(:microsecond),
            to_string(event.direction),
            event.host,
            event.path,
            Event.normalize_method(event.method),
            event.status,
            to_string(event.status_class),
            event.duration_ms,
            event.request_body,
            event.response_body,
            event.consumer,
            if(event.slow, do: 1, else: 0),
            event.dedup_key
          ]
        )

      update_aggregate(db, event)

      :ok
    end

    defp update_aggregate(db, %Event{direction: :outbound} = event) do
      host = event.host || "unknown"
      key = "host:#{host}"

      upsert_aggregate(db, key, event)

      endpoint_key = "endpoint:#{host}:#{event.path}"
      upsert_aggregate(db, endpoint_key, event)
    end

    defp update_aggregate(db, %Event{direction: :inbound} = event) do
      route_key = "route:#{Event.normalize_method(event.method)}:#{event.path}"
      upsert_aggregate(db, route_key, event)

      if event.consumer do
        consumer_key = "consumer:#{event.consumer}"
        upsert_aggregate(db, consumer_key, event)
      end
    end

    defp upsert_aggregate(db, key, event) do
      error_inc = if error_status?(event.status), do: 1, else: 0

      :ok =
        sql_exec(
          db,
          "INSERT INTO aggregates
           (key, type, requests, errors, total_duration, last_seen)
           VALUES (?1, ?2, 1, ?3, ?4, ?5)
           ON CONFLICT(key) DO UPDATE SET
             requests = requests + 1,
             errors = errors + ?3,
             total_duration = total_duration + ?4,
             last_seen = ?5;",
          [
            key,
            String.split(key, ":") |> hd(),
            error_inc,
            event.duration_ms || 0.0,
            System.system_time(:microsecond)
          ]
        )
    end

    defp error_status?(status) when is_integer(status) and status >= 400, do: true
    defp error_status?(_), do: false

    @impl true
    def prune do
      db = conn()

      max_age_seconds =
        Application.get_env(:monitorex, :sqlite_max_age_seconds, 7 * 24 * 60 * 60)

      cutoff = System.system_time(:second) - max_age_seconds

      :ok = sql_exec(db, "DELETE FROM events WHERE timestamp < ?1;", [cutoff * 1_000_000])
      :ok = sql_exec(db, "DELETE FROM aggregates WHERE last_seen < ?1;", [cutoff * 1_000_000])
      :ok = sql_exec(db, "VACUUM;", [])

      :ok
    end

    # ── Read callbacks ──

    @impl true
    def list_hosts do
      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT key, requests, errors, total_duration, last_seen
           FROM aggregates WHERE type = 'host' ORDER BY requests DESC;",
          []
        )

      Enum.map(rows, fn [key, requests, errors, total_duration, _last_seen] ->
        req = requests || 0
        err = errors || 0
        td = total_duration || 0.0

        %{
          host: String.replace_prefix(key, "host:", ""),
          requests: req,
          errors: err,
          error_rate: if(req > 0, do: err / req, else: 0.0),
          total_duration: td,
          avg_latency: if(req > 0, do: td / req, else: 0.0),
          p50: nil,
          p95: nil,
          p99: nil
        }
      end)
    end

    @impl true
    def list_endpoints_for_host(host) do
      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT key, requests, errors, total_duration, last_seen
           FROM aggregates WHERE type = 'endpoint' AND key LIKE ?1;",
          ["endpoint:#{host}:%"]
        )

      Enum.map(rows, fn [key, requests, errors, total_duration, last_seen] ->
        req = requests || 0
        td = total_duration || 0.0

        %{
          path: key |> String.split(":", parts: 3) |> Enum.at(2),
          requests: req,
          errors: errors || 0,
          total_duration: td,
          avg_latency: if(req > 0, do: td / req, else: 0.0),
          last_seen: last_seen
        }
      end)
    end

    @impl true
    def list_recent_outbound(opts \\ []) do
      limit = Keyword.get(opts, :limit, @default_limit)
      offset = Keyword.get(opts, :offset, 0)
      status_class = Keyword.get(opts, :status_class)
      host = Keyword.get(opts, :host)

      {where, params} = build_event_filter("direction = 'outbound'", status_class, host)

      sql =
        "SELECT * FROM events WHERE #{where} ORDER BY timestamp DESC LIMIT ?#{length(params) + 1} OFFSET ?#{length(params) + 2};"

      {:ok, rows} = sql_query(conn(), sql, params ++ [limit, offset])
      Enum.map(rows, &row_to_event/1)
    end

    @impl true
    def list_routes do
      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT key, requests, errors, total_duration, last_seen
           FROM aggregates WHERE type = 'route' ORDER BY requests DESC;",
          []
        )

      Enum.map(rows, fn [key, requests, errors, total_duration, _last_seen] ->
        req = requests || 0
        err = errors || 0
        td = total_duration || 0.0
        [method, path] = String.split(String.replace_prefix(key, "route:", ""), ":", parts: 2)

        %{
          method: method,
          path: path,
          requests: req,
          errors: err,
          error_rate: if(req > 0, do: err / req, else: 0.0),
          total_duration: td,
          avg_latency: if(req > 0, do: td / req, else: 0.0),
          p50: nil,
          p95: nil,
          p99: nil
        }
      end)
    end

    @impl true
    def list_consumers do
      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT key, requests, errors, total_duration, last_seen
           FROM aggregates WHERE type = 'consumer' ORDER BY requests DESC;",
          []
        )

      Enum.map(rows, fn [key, requests, errors, total_duration, last_seen] ->
        %{
          consumer: String.replace_prefix(key, "consumer:", ""),
          requests: requests || 0,
          errors: errors || 0,
          total_duration: total_duration || 0.0,
          last_seen: last_seen
        }
      end)
    end

    @impl true
    def list_recent_inbound(opts \\ []) do
      limit = Keyword.get(opts, :limit, @default_limit)
      offset = Keyword.get(opts, :offset, 0)
      status_class = Keyword.get(opts, :status_class)
      consumer = Keyword.get(opts, :consumer)
      route = Keyword.get(opts, :route)

      base = "direction = 'inbound'"
      base = if status_class, do: base <> " AND status_class = '#{status_class}'", else: base
      base = if consumer, do: base <> " AND consumer = '#{consumer}'", else: base

      base =
        if route do
          [method, path] = String.split(route, ":", parts: 2)
          base <> " AND method = '#{method}' AND path = '#{path}'"
        else
          base
        end

      sql = "SELECT * FROM events WHERE #{base} ORDER BY timestamp DESC LIMIT ?1 OFFSET ?2;"

      {:ok, rows} = sql_query(conn(), sql, [limit, offset])
      Enum.map(rows, &row_to_event/1)
    end

    @impl true
    def list_consumers_for_route(route_key) do
      [method, path] = String.split(route_key, ":", parts: 2)

      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT consumer,
                  COUNT(*) as requests,
                  SUM(CASE WHEN status >= 400 THEN 1 ELSE 0 END) as errors,
                  SUM(duration_ms) as total_duration,
                  MAX(timestamp) as last_seen
           FROM events
           WHERE direction = 'inbound' AND method = ?1 AND path = ?2 AND consumer IS NOT NULL
           GROUP BY consumer
           ORDER BY requests DESC;",
          [method, path]
        )

      Enum.map(rows, fn [consumer, requests, errors, total_duration, last_seen] ->
        req = requests || 0
        td = total_duration || 0.0

        %{
          consumer: consumer,
          requests: req,
          errors: errors || 0,
          total_duration: td,
          avg_latency: if(req > 0, do: td / req, else: 0.0),
          last_seen: last_seen
        }
      end)
    end

    @impl true
    def get_event(timestamp) when is_integer(timestamp) do
      {:ok, rows} =
        sql_query(conn(), "SELECT * FROM events WHERE timestamp = ?1 LIMIT 1;", [timestamp])

      case rows do
        [row] -> row_to_event(row)
        [] -> nil
      end
    end

    @impl true
    def count_recent_outbound(opts \\ []) do
      status_class = Keyword.get(opts, :status_class)
      host = Keyword.get(opts, :host)

      {where, params} = build_event_filter("direction = 'outbound'", status_class, host)

      {:ok, rows} = sql_query(conn(), "SELECT COUNT(*) FROM events WHERE #{where};", params)

      case rows do
        [[count]] -> count || 0
        _ -> 0
      end
    end

    @impl true
    def count_recent_inbound(opts \\ []) do
      status_class = Keyword.get(opts, :status_class)
      consumer = Keyword.get(opts, :consumer)
      route = Keyword.get(opts, :route)

      base = "direction = 'inbound'"
      base = if status_class, do: base <> " AND status_class = '#{status_class}'", else: base
      base = if consumer, do: base <> " AND consumer = '#{consumer}'", else: base

      base =
        if route do
          [method, path] = String.split(route, ":", parts: 2)
          base <> " AND method = '#{method}' AND path = '#{path}'"
        else
          base
        end

      {:ok, rows} = sql_query(conn(), "SELECT COUNT(*) FROM events WHERE #{base};", [])

      case rows do
        [[count]] -> count || 0
        _ -> 0
      end
    end

    @impl true
    def list_slow_outbound(opts \\ []) do
      limit = Keyword.get(opts, :limit, 50)

      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT * FROM events WHERE direction = 'outbound' AND slow = 1 ORDER BY timestamp DESC LIMIT ?1;",
          [limit]
        )

      Enum.map(rows, &row_to_event/1)
    end

    @impl true
    def list_slow_inbound(opts \\ []) do
      limit = Keyword.get(opts, :limit, 50)

      {:ok, rows} =
        sql_query(
          conn(),
          "SELECT * FROM events WHERE direction = 'inbound' AND slow = 1 ORDER BY timestamp DESC LIMIT ?1;",
          [limit]
        )

      Enum.map(rows, &row_to_event/1)
    end

    # ── Private helpers ──

    defp build_event_filter(base, nil, nil), do: {base, []}

    defp build_event_filter(base, status_class, nil),
      do: {base <> " AND status_class = '#{status_class}'", []}

    defp build_event_filter(base, nil, host), do: {base <> " AND host = ?1", [host]}

    defp build_event_filter(base, status_class, host) do
      {base <> " AND status_class = '#{status_class}' AND host = ?1", [host]}
    end

    defp sql_exec(db, sql, params) do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(db, sql)
      :ok = Exqlite.Sqlite3.bind(stmt, params)

      try do
        case Exqlite.Sqlite3.step(db, stmt) do
          :done -> :ok
          :busy -> :ok
          _ -> :ok
        end
      after
        Exqlite.Sqlite3.release(db, stmt)
      end
    end

    defp sql_query(db, sql, params) do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(db, sql)
      :ok = Exqlite.Sqlite3.bind(stmt, params)

      try do
        Exqlite.Sqlite3.fetch_all(db, stmt)
      after
        Exqlite.Sqlite3.release(db, stmt)
      end
    end

    # Row order must match SELECT * FROM events
    defp row_to_event([
           _id,
           timestamp,
           direction,
           host,
           path,
           method,
           status,
           status_class,
           duration_ms,
           request_body,
           response_body,
           consumer,
           slow,
           dedup_key
         ]) do
      %Event{
        timestamp: timestamp,
        direction: safe_atom(direction),
        host: host,
        path: path,
        method: safe_atom(method),
        status: status,
        status_class: safe_atom(status_class),
        duration_ms: duration_ms,
        request_body: request_body,
        response_body: response_body,
        consumer: consumer,
        slow: slow == 1,
        dedup_key: dedup_key,
        source: nil,
        full_url: nil,
        error: nil,
        request_headers: nil,
        response_headers: nil
      }
    end

    defp safe_atom(nil), do: nil
    defp safe_atom(str) when is_binary(str), do: String.to_existing_atom(str)
    defp safe_atom(other), do: other
  end
end
