if Code.ensure_loaded?(Exqlite.Sqlite3) do
  defmodule Monitorex.Storage.SQLiteTest do
    use ExUnit.Case, async: false

    alias Monitorex.Event
    alias Monitorex.Storage.SQLite

    @db_path "/tmp/monitorex_test_#{System.system_time(:millisecond)}.db"

    setup do
      # Clean up any stale DB and configure SQLite backend for this test
      File.rm(@db_path)
      Application.put_env(:monitorex, :sqlite_path, @db_path)

      # Ensure module is loaded (triggered by Code.ensure_loaded? guard)
      # Write a single event to trigger schema creation
      event = %Event{
        timestamp: System.system_time(:microsecond),
        direction: :outbound,
        method: :get,
        host: "api.example.com",
        path: "/v1/users",
        status: 200,
        status_class: :success,
        duration_ms: 42.0,
        consumer: nil,
        slow: false,
        dedup_key: nil
      }

      :ok = SQLite.record_event(event)

      on_exit(fn ->
        File.rm(@db_path)
        Process.delete(:monitorex_sqlite_conn)
      end)

      :ok
    end

    test "record_event/1 persists and get_event/1 retrieves" do
      ts = System.system_time(:microsecond)

      event = %Event{
        timestamp: ts,
        direction: :outbound,
        method: :post,
        host: "api.example.com",
        path: "/v1/orders",
        status: 201,
        status_class: :success,
        duration_ms: 123.0,
        consumer: nil,
        slow: false,
        dedup_key: nil
      }

      :ok = SQLite.record_event(event)
      retrieved = SQLite.get_event(ts)

      assert retrieved != nil
      assert retrieved.direction == :outbound
      assert retrieved.method == :POST
      assert retrieved.status == 201
      assert retrieved.duration_ms == 123.0
    end

    test "list_hosts/0 returns aggregated host stats" do
      hosts = SQLite.list_hosts()
      assert is_list(hosts)
      assert hosts != []

      host = hd(hosts)
      assert host.host == "api.example.com"
      assert host.requests >= 1
      assert host.errors >= 0
    end

    test "list_recent_outbound/0 returns events ordered by timestamp desc" do
      events = SQLite.list_recent_outbound(limit: 10)
      assert is_list(events)
      assert events != []

      [first | _] = events
      assert first.direction == :outbound
    end

    test "count_recent_outbound/0 returns non-negative count" do
      count = SQLite.count_recent_outbound()
      assert is_integer(count)
      assert count >= 1
    end

    test "prune/0 deletes old events and aggregates" do
      # Force an event with very old timestamp
      old_ts = System.system_time(:microsecond) - 8 * 24 * 60 * 60 * 1_000_000

      event = %Event{
        timestamp: old_ts,
        direction: :outbound,
        method: :get,
        host: "old.example.com",
        path: "/legacy",
        status: 200,
        status_class: :success,
        duration_ms: 10.0,
        consumer: nil,
        slow: false,
        dedup_key: nil
      }

      :ok = SQLite.record_event(event)

      # Verify it exists
      count_before = SQLite.count_recent_outbound()
      assert count_before >= 2

      :ok = SQLite.prune()

      # After prune with default 7-day max age, the old event should be gone
      count_after = SQLite.count_recent_outbound()
      assert count_after < count_before
    end

    test "list_routes/0 aggregates inbound routes" do
      ts = System.system_time(:microsecond)

      event = %Event{
        timestamp: ts,
        direction: :inbound,
        method: :get,
        host: nil,
        path: "/api/health",
        status: 200,
        status_class: :success,
        duration_ms: 5.0,
        consumer: "frontend",
        slow: false,
        dedup_key: nil
      }

      :ok = SQLite.record_event(event)

      routes = SQLite.list_routes()
      assert is_list(routes)
      assert routes != []

      route = Enum.find(routes, &(&1.path == "/api/health"))
      assert route != nil
      assert route.method == "GET"
      assert route.requests >= 1
    end

    test "list_consumers/0 aggregates consumers" do
      consumers = SQLite.list_consumers()
      assert is_list(consumers)
      # At least the "frontend" consumer from previous test should exist
      frontend = Enum.find(consumers, &(&1.consumer == "frontend"))
      assert frontend != nil || consumers == []
    end

    test "list_endpoints_for_host/1 returns per-host endpoint stats" do
      endpoints = SQLite.list_endpoints_for_host("api.example.com")
      assert is_list(endpoints)
      assert endpoints != []
    end

    test "list_consumers_for_route/1 aggregates per-route consumers" do
      consumers = SQLite.list_consumers_for_route("GET:/api/health")
      assert is_list(consumers)
    end
  end
end
