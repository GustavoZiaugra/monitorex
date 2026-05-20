defmodule Monitorex.StorageTest do
  use ExUnit.Case, async: false

  alias Monitorex.Storage
  alias Monitorex.Event

  # ── Table names ──

  @outbound_hosts :monitorex_outbound_hosts
  @outbound_endpoints :monitorex_outbound_endpoints
  @outbound_recent :monitorex_outbound_recent
  @outbound_duration_samples :monitorex_outbound_duration_samples

  @inbound_routes :monitorex_inbound_routes
  @inbound_consumers :monitorex_inbound_consumers
  @inbound_recent :monitorex_inbound_recent
  @inbound_duration_samples :monitorex_inbound_duration_samples

  setup do
    # Clean up any leftover ETS tables from previous runs
    Enum.each(
      [
        @outbound_hosts,
        @outbound_endpoints,
        @outbound_recent,
        @outbound_duration_samples,
        @inbound_routes,
        @inbound_consumers,
        @inbound_recent,
        @inbound_duration_samples,
        :monitorex_slow_outbound,
        :monitorex_slow_inbound
      ],
      fn table ->
        try do
          :ets.delete(table)
        rescue
          _ -> :ok
        end
      end
    )

    :ok
  end

  # ── Helpers ──

  defp create_tables do
    :ets.new(@outbound_hosts, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@outbound_endpoints, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@outbound_recent, [:public, :named_table, :ordered_set, read_concurrency: true])
    :ets.new(@outbound_duration_samples, [:public, :named_table, :bag, read_concurrency: true])
    :ets.new(@inbound_routes, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@inbound_consumers, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@inbound_recent, [:public, :named_table, :ordered_set, read_concurrency: true])
    :ets.new(@inbound_duration_samples, [:public, :named_table, :bag, read_concurrency: true])

    :ets.new(:monitorex_slow_outbound, [
      :public,
      :named_table,
      :ordered_set,
      read_concurrency: true
    ])

    :ets.new(:monitorex_slow_inbound, [
      :public,
      :named_table,
      :ordered_set,
      read_concurrency: true
    ])

    :ok
  end

  defp insert_outbound_recent(ts, event) do
    :ets.insert(@outbound_recent, {ts, event})
  end

  defp insert_inbound_recent(ts, event) do
    :ets.insert(@inbound_recent, {ts, event})
  end

  # ── list_hosts/0 ──

  describe "list_hosts/0" do
    test "returns empty list when table is missing" do
      assert Storage.list_hosts() == []
    end

    test "returns empty list when table is empty" do
      create_tables()
      assert Storage.list_hosts() == []
    end

    test "returns host aggregates sorted by requests descending" do
      create_tables()

      :ets.insert(
        @outbound_hosts,
        {"host-a", %{requests: 5, errors: 1, total_duration: 250.0, last_seen: 1000}}
      )

      :ets.insert(
        @outbound_hosts,
        {"host-b", %{requests: 10, errors: 2, total_duration: 500.0, last_seen: 2000}}
      )

      :ets.insert(
        @outbound_hosts,
        {"host-c", %{requests: 3, errors: 0, total_duration: 90.0, last_seen: 3000}}
      )

      result = Storage.list_hosts()
      assert length(result) == 3
      assert Enum.map(result, & &1.host) == ["host-b", "host-a", "host-c"]
    end

    test "computes avg_latency and error_rate" do
      create_tables()

      :ets.insert(
        @outbound_hosts,
        {"host-a", %{requests: 10, errors: 2, total_duration: 500.0, last_seen: 1000}}
      )

      [entry] = Storage.list_hosts()
      assert entry.host == "host-a"
      assert entry.requests == 10
      assert entry.errors == 2
      assert entry.total_duration == 500.0
      assert_in_delta entry.avg_latency, 50.0, 0.001
      assert_in_delta entry.error_rate, 0.2, 0.001
    end

    test "handles zero requests gracefully" do
      create_tables()

      :ets.insert(
        @outbound_hosts,
        {"host-a", %{requests: 0, errors: 0, total_duration: 0.0, last_seen: 1000}}
      )

      [entry] = Storage.list_hosts()
      assert entry.avg_latency == 0.0
      assert entry.error_rate == 0.0
    end

    test "computes percentiles from duration samples" do
      create_tables()

      :ets.insert(
        @outbound_hosts,
        {"host-a", %{requests: 5, errors: 0, total_duration: 150.0, last_seen: 1000}}
      )

      # Insert duration samples
      Enum.each([10.0, 20.0, 30.0, 40.0, 50.0], fn ms ->
        :ets.insert(@outbound_duration_samples, {"host-a", ms})
      end)

      [entry] = Storage.list_hosts()
      # p50: rank = max(1, round(5 * 50 / 100)) = max(1, 3) = 3 → samples[2] = 30.0
      assert entry.p50 == 30.0
      # p95: rank = max(1, round(5 * 95 / 100)) = max(1, 5) = 5 → samples[4] = 50.0
      assert entry.p95 == 50.0
      # p99: rank = max(1, round(5 * 99 / 100)) = max(1, 5) = 5 → samples[4] = 50.0
      assert entry.p99 == 50.0
    end

    test "returns nil percentiles when no duration samples" do
      create_tables()

      :ets.insert(
        @outbound_hosts,
        {"host-a", %{requests: 5, errors: 0, total_duration: 150.0, last_seen: 1000}}
      )

      [entry] = Storage.list_hosts()
      assert entry.p50 == nil
      assert entry.p95 == nil
      assert entry.p99 == nil
    end

    test "returns nil percentiles when missing duration_samples table" do
      create_tables()

      # Delete the duration samples table
      :ets.delete(@outbound_duration_samples)

      :ets.insert(
        @outbound_hosts,
        {"host-a", %{requests: 5, errors: 0, total_duration: 150.0, last_seen: 1000}}
      )

      [entry] = Storage.list_hosts()
      assert entry.p50 == nil
      assert entry.p95 == nil
      assert entry.p99 == nil
    end
  end

  # ── list_endpoints_for_host/1 ──

  describe "list_endpoints_for_host/1" do
    test "returns empty list when table is missing" do
      assert Storage.list_endpoints_for_host("host-a") == []
    end

    test "returns endpoints for matching host only" do
      create_tables()

      :ets.insert(
        @outbound_endpoints,
        {{"host-a", "/users"}, %{requests: 5, errors: 1, total_duration: 250.0, last_seen: 1000}}
      )

      :ets.insert(
        @outbound_endpoints,
        {{"host-a", "/posts"}, %{requests: 3, errors: 0, total_duration: 90.0, last_seen: 2000}}
      )

      :ets.insert(
        @outbound_endpoints,
        {{"host-b", "/other"}, %{requests: 10, errors: 2, total_duration: 500.0, last_seen: 3000}}
      )

      result = Storage.list_endpoints_for_host("host-a")
      assert length(result) == 2

      paths = Enum.map(result, & &1.path) |> Enum.sort()
      assert paths == ["/posts", "/users"]
    end

    test "computes avg_latency" do
      create_tables()

      :ets.insert(
        @outbound_endpoints,
        {{"host-a", "/path"}, %{requests: 10, errors: 2, total_duration: 500.0, last_seen: 1000}}
      )

      [entry] = Storage.list_endpoints_for_host("host-a")
      assert entry.path == "/path"
      assert entry.requests == 10
      assert entry.errors == 2
      assert entry.total_duration == 500.0
      assert_in_delta entry.avg_latency, 50.0, 0.001
      assert entry.last_seen == 1000
    end

    test "returns empty list for host with no endpoints" do
      create_tables()

      :ets.insert(
        @outbound_endpoints,
        {{"host-b", "/path"}, %{requests: 1, errors: 0, total_duration: 10.0, last_seen: 1000}}
      )

      assert Storage.list_endpoints_for_host("host-a") == []
    end
  end

  # ── list_recent_outbound/1 ──

  describe "list_recent_outbound/1" do
    test "returns empty list when table is missing" do
      assert Storage.list_recent_outbound() == []
    end

    test "returns recent outbound events in reverse chronological order" do
      create_tables()

      e1 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/users",
        status: 200,
        status_class: :success,
        duration_ms: 10.0
      }

      e2 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "POST",
        host: "host-a",
        path: "/posts",
        status: 201,
        status_class: :success,
        duration_ms: 20.0
      }

      insert_outbound_recent(1, e1)
      insert_outbound_recent(2, e2)

      result = Storage.list_recent_outbound()
      assert length(result) == 2
      # Most recent first (higher timestamp = more recent)
      assert Enum.map(result, & &1.path) == ["/posts", "/users"]
    end

    test "respects limit option" do
      create_tables()

      for i <- 1..3 do
        e = %Event{
          source: :tesla,
          direction: :outbound,
          method: "GET",
          host: "host-a",
          path: "/#{i}",
          status: 200,
          status_class: :success
        }

        insert_outbound_recent(i, e)
      end

      assert length(Storage.list_recent_outbound(limit: 2)) == 2
    end

    test "default limit is 50" do
      create_tables()

      for i <- 1..60 do
        e = %Event{
          source: :tesla,
          direction: :outbound,
          method: "GET",
          host: "host-a",
          path: "/#{i}",
          status: 200,
          status_class: :success
        }

        insert_outbound_recent(i, e)
      end

      assert length(Storage.list_recent_outbound()) == 50
    end

    test "returns all events when limit exceeds count" do
      create_tables()

      e = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/1",
        status: 200,
        status_class: :success
      }

      insert_outbound_recent(1, e)

      assert length(Storage.list_recent_outbound(limit: 100)) == 1
    end

    test "filters by status_class" do
      create_tables()

      e1 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/ok",
        status: 200,
        status_class: :success
      }

      e2 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/err",
        status: 500,
        status_class: :server_error
      }

      insert_outbound_recent(1, e1)
      insert_outbound_recent(2, e2)

      result = Storage.list_recent_outbound(status_class: :server_error)
      assert length(result) == 1
      assert hd(result).path == "/err"
    end

    test "filters by host exact match" do
      create_tables()

      e1 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/a",
        status: 200,
        status_class: :success
      }

      e2 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-b",
        path: "/b",
        status: 200,
        status_class: :success
      }

      insert_outbound_recent(1, e1)
      insert_outbound_recent(2, e2)

      result = Storage.list_recent_outbound(host: "host-a")
      assert length(result) == 1
      assert hd(result).host == "host-a"
    end

    test "filters by both status_class and host" do
      create_tables()

      e1 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/a",
        status: 500,
        status_class: :server_error
      }

      e2 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-b",
        path: "/b",
        status: 500,
        status_class: :server_error
      }

      e3 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/c",
        status: 200,
        status_class: :success
      }

      insert_outbound_recent(1, e1)
      insert_outbound_recent(2, e2)
      insert_outbound_recent(3, e3)

      result = Storage.list_recent_outbound(status_class: :server_error, host: "host-a")
      assert length(result) == 1
      assert hd(result).path == "/a"
    end

    test "nil status_class filter means no filter" do
      create_tables()

      e1 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/ok",
        status: 200,
        status_class: :success
      }

      e2 = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/err",
        status: 500,
        status_class: :server_error
      }

      insert_outbound_recent(1, e1)
      insert_outbound_recent(2, e2)

      result = Storage.list_recent_outbound(status_class: nil)
      assert length(result) == 2
    end
  end

  # ── list_routes/0 ──

  describe "list_routes/0" do
    test "returns empty list when table is missing" do
      assert Storage.list_routes() == []
    end

    test "returns route aggregates with parsed method and path" do
      create_tables()

      :ets.insert(
        @inbound_routes,
        {"GET:/api/users", %{requests: 10, errors: 1, total_duration: 500.0, last_seen: 1000}}
      )

      :ets.insert(
        @inbound_routes,
        {"POST:/api/orders", %{requests: 5, errors: 0, total_duration: 250.0, last_seen: 2000}}
      )

      result = Storage.list_routes()
      assert length(result) == 2

      methods = Enum.map(result, & &1.method) |> Enum.sort()
      assert methods == ["GET", "POST"]
    end

    test "sorts by requests descending" do
      create_tables()

      :ets.insert(
        @inbound_routes,
        {"GET:/low", %{requests: 3, errors: 0, total_duration: 30.0, last_seen: 1000}}
      )

      :ets.insert(
        @inbound_routes,
        {"GET:/high", %{requests: 20, errors: 2, total_duration: 400.0, last_seen: 2000}}
      )

      result = Storage.list_routes()
      assert Enum.map(result, & &1.path) == ["/high", "/low"]
    end

    test "computes error_rate, avg_latency, and percentiles" do
      create_tables()

      :ets.insert(
        @inbound_routes,
        {"GET:/api/users", %{requests: 10, errors: 2, total_duration: 500.0, last_seen: 1000}}
      )

      # Duration samples for percentiles
      Enum.each([10.0, 20.0, 30.0, 40.0, 50.0], fn ms ->
        :ets.insert(@inbound_duration_samples, {"GET:/api/users", ms})
      end)

      [entry] = Storage.list_routes()
      assert entry.method == "GET"
      assert entry.path == "/api/users"
      assert entry.requests == 10
      assert entry.errors == 2
      assert_in_delta entry.avg_latency, 50.0, 0.001
      assert_in_delta entry.error_rate, 0.2, 0.001
      assert entry.p50 == 30.0
      assert entry.p95 == 50.0
      assert entry.p99 == 50.0
    end

    test "returns nil percentiles when no duration samples" do
      create_tables()

      :ets.insert(
        @inbound_routes,
        {"GET:/api/users", %{requests: 5, errors: 0, total_duration: 150.0, last_seen: 1000}}
      )

      [entry] = Storage.list_routes()
      assert entry.p50 == nil
      assert entry.p95 == nil
      assert entry.p99 == nil
    end
  end

  # ── list_consumers/0 ──

  describe "list_consumers/0" do
    test "returns empty list when table is missing" do
      assert Storage.list_consumers() == []
    end

    test "returns consumer aggregates sorted by requests descending" do
      create_tables()

      :ets.insert(
        @inbound_consumers,
        {"alice", %{requests: 10, errors: 1, total_duration: 500.0, last_seen: 1000}}
      )

      :ets.insert(
        @inbound_consumers,
        {"bob", %{requests: 20, errors: 2, total_duration: 1000.0, last_seen: 2000}}
      )

      result = Storage.list_consumers()
      assert length(result) == 2
      assert Enum.map(result, & &1.consumer) == ["bob", "alice"]
    end

    test "includes all aggregate fields" do
      create_tables()

      :ets.insert(
        @inbound_consumers,
        {"alice", %{requests: 10, errors: 1, total_duration: 500.0, last_seen: 1000}}
      )

      [entry] = Storage.list_consumers()
      assert entry.consumer == "alice"
      assert entry.requests == 10
      assert entry.errors == 1
      assert entry.total_duration == 500.0
      assert entry.last_seen == 1000
    end
  end

  # ── list_recent_inbound/1 ──

  describe "list_recent_inbound/1" do
    test "returns empty list when table is missing" do
      assert Storage.list_recent_inbound() == []
    end

    test "returns recent inbound events in reverse chronological order" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "alice",
        duration_ms: 10.0
      }

      e2 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 201,
        status_class: :success,
        consumer: "bob",
        duration_ms: 20.0
      }

      insert_inbound_recent(1, e1)
      insert_inbound_recent(2, e2)

      result = Storage.list_recent_inbound()
      assert length(result) == 2
      # Most recent first
      assert Enum.map(result, & &1.path) == ["/api/orders", "/api/users"]
    end

    test "respects limit option" do
      create_tables()

      for i <- 1..3 do
        e = %Event{
          source: :phoenix,
          direction: :inbound,
          method: "GET",
          path: "/#{i}",
          status: 200,
          status_class: :success,
          consumer: "tester"
        }

        insert_inbound_recent(i, e)
      end

      assert length(Storage.list_recent_inbound(limit: 2)) == 2
    end

    test "filters by consumer" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/a",
        status: 200,
        status_class: :success,
        consumer: "alice"
      }

      e2 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/b",
        status: 200,
        status_class: :success,
        consumer: "bob"
      }

      insert_inbound_recent(1, e1)
      insert_inbound_recent(2, e2)

      result = Storage.list_recent_inbound(consumer: "alice")
      assert length(result) == 1
      assert hd(result).consumer == "alice"
    end

    test "filters by route" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "alice"
      }

      e2 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 201,
        status_class: :success,
        consumer: "bob"
      }

      insert_inbound_recent(1, e1)
      insert_inbound_recent(2, e2)

      result = Storage.list_recent_inbound(route: "GET:/api/users")
      assert length(result) == 1
      assert hd(result).path == "/api/users"
    end

    test "filters by both consumer and route" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "alice"
      }

      e2 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "bob"
      }

      e3 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 201,
        status_class: :success,
        consumer: "alice"
      }

      insert_inbound_recent(1, e1)
      insert_inbound_recent(2, e2)
      insert_inbound_recent(3, e3)

      result = Storage.list_recent_inbound(consumer: "alice", route: "GET:/api/users")
      assert length(result) == 1
      assert hd(result).consumer == "alice"
      assert hd(result).path == "/api/users"
    end
  end

  # ── list_consumers_for_route/1 ──

  describe "list_consumers_for_route/1" do
    test "returns empty list when table is missing" do
      assert Storage.list_consumers_for_route("GET:/api/users") == []
    end

    test "returns consumer breakdown for a route grouped by consumer" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "alice",
        duration_ms: 10.0,
        timestamp: 100
      }

      e2 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "bob",
        duration_ms: 20.0,
        timestamp: 200
      }

      e3 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 500,
        status_class: :server_error,
        consumer: "alice",
        duration_ms: 30.0,
        timestamp: 300
      }

      e4 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 201,
        status_class: :success,
        consumer: "alice",
        duration_ms: 5.0,
        timestamp: 400
      }

      insert_inbound_recent(1, e1)
      insert_inbound_recent(2, e2)
      insert_inbound_recent(3, e3)
      insert_inbound_recent(4, e4)

      result = Storage.list_consumers_for_route("GET:/api/users")
      assert length(result) == 2

      # alice: 2 requests, 1 error, total_duration 40.0
      alice = Enum.find(result, &(&1.consumer == "alice"))
      assert alice.requests == 2
      assert alice.errors == 1
      assert_in_delta alice.total_duration, 40.0, 0.001
      assert_in_delta alice.avg_latency, 20.0, 0.001
      assert alice.last_seen == 300

      # bob: 1 request, 0 errors, total_duration 20.0
      bob = Enum.find(result, &(&1.consumer == "bob"))
      assert bob.requests == 1
      assert bob.errors == 0
      assert_in_delta bob.total_duration, 20.0, 0.001
      assert_in_delta bob.avg_latency, 20.0, 0.001
      assert bob.last_seen == 200
    end

    test "sorts by requests descending" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "bob",
        duration_ms: 10.0,
        timestamp: 100
      }

      e2 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "alice",
        duration_ms: 10.0,
        timestamp: 200
      }

      e3 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: "alice",
        duration_ms: 10.0,
        timestamp: 300
      }

      insert_inbound_recent(1, e1)
      insert_inbound_recent(2, e2)
      insert_inbound_recent(3, e3)

      result = Storage.list_consumers_for_route("GET:/api/users")
      assert length(result) == 2
      assert hd(result).consumer == "alice"
      assert hd(result).requests == 2
    end

    test "ignores events with nil consumer" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/users",
        status: 200,
        status_class: :success,
        consumer: nil,
        duration_ms: 10.0,
        timestamp: 100
      }

      insert_inbound_recent(1, e1)

      assert Storage.list_consumers_for_route("GET:/api/users") == []
    end

    test "ignores events from other routes" do
      create_tables()

      e1 = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 200,
        status_class: :success,
        consumer: "alice",
        duration_ms: 10.0,
        timestamp: 100
      }

      insert_inbound_recent(1, e1)

      assert Storage.list_consumers_for_route("GET:/api/users") == []
    end
  end

  # ── Edge cases ──

  describe "edge cases" do
    test "missing tables return empty lists for all functions" do
      # No tables created at all
      assert Storage.list_hosts() == []
      assert Storage.list_endpoints_for_host("x") == []
      assert Storage.list_recent_outbound() == []
      assert Storage.list_routes() == []
      assert Storage.list_consumers() == []
      assert Storage.list_recent_inbound() == []
      assert Storage.list_consumers_for_route("GET:/x") == []
    end

    test "empty tables return empty lists" do
      create_tables()

      assert Storage.list_hosts() == []
      assert Storage.list_endpoints_for_host("x") == []
      assert Storage.list_recent_outbound() == []
      assert Storage.list_routes() == []
      assert Storage.list_consumers() == []
      assert Storage.list_recent_inbound() == []
      assert Storage.list_consumers_for_route("GET:/x") == []
    end
  end

  describe "get_event/1" do
    test "returns nil when tables are missing" do
      assert Storage.get_event(1) == nil
    end

    test "fetches outbound event by timestamp" do
      create_tables()

      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "host-a",
        path: "/users",
        status: 200,
        status_class: :success,
        timestamp: 123
      }

      :ets.insert(:monitorex_outbound_recent, {123, event})

      assert Storage.get_event(123) == event
    end

    test "fetches inbound event by timestamp" do
      create_tables()

      event = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 201,
        status_class: :success,
        timestamp: 456
      }

      :ets.insert(:monitorex_inbound_recent, {456, event})

      assert Storage.get_event(456) == event
    end

    test "returns nil when timestamp is not found" do
      create_tables()

      assert Storage.get_event(999) == nil
    end
  end
end
