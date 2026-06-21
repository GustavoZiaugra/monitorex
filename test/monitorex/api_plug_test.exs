defmodule Monitorex.ApiPlugTest do
  use ExUnit.Case, async: false

  alias Monitorex.ApiPlug
  alias Monitorex.Event
  alias Monitorex.LiveComponentFixtures
  alias Plug.Test

  @tables [
    :monitorex_outbound_hosts,
    :monitorex_outbound_endpoints,
    :monitorex_outbound_recent,
    :monitorex_outbound_duration_samples,
    :monitorex_inbound_routes,
    :monitorex_inbound_consumers,
    :monitorex_inbound_recent,
    :monitorex_inbound_duration_samples
  ]

  setup do
    LiveComponentFixtures.reset_ets_tables(@tables)
    :ok
  end

  defp call(path_info, params \\ %{}, method \\ :get) do
    conn =
      method
      |> Test.conn("/")
      |> Map.put(:path_info, path_info)
      |> Map.put(:params, params)

    ApiPlug.call(conn, [])
  end

  describe "init/1" do
    test "returns opts unchanged" do
      assert ApiPlug.init(foo: :bar) == [foo: :bar]
    end
  end

  describe "CORS" do
    test "OPTIONS request returns 204 with CORS headers" do
      conn = call(["hosts"], %{}, :options)
      assert conn.status == 204
      assert {"access-control-allow-origin", "*"} in conn.resp_headers
    end
  end

  describe "GET /api/hosts" do
    test "returns list of hosts" do
      :ets.insert(:monitorex_outbound_hosts, {"host-a", %{requests: 10, errors: 1, total_duration: 100.0, last_seen: 1000}})

      conn = call(["hosts"])
      assert conn.status == 200
      assert %{"ok" => true, "data" => [host]} = Jason.decode!(conn.resp_body)
      assert host["host"] == "host-a"
    end
  end

  describe "GET /api/hosts/:host" do
    test "returns host detail with endpoints" do
      :ets.insert(:monitorex_outbound_hosts, {"host-a", %{requests: 10, errors: 1, total_duration: 100.0, last_seen: 1000}})
      :ets.insert(:monitorex_outbound_endpoints, {{"host-a", "/x"}, %{requests: 5, errors: 0, total_duration: 50.0, last_seen: 1000}})

      conn = call(["hosts", "host-a"])
      assert conn.status == 200
      assert %{"ok" => true, "data" => data} = Jason.decode!(conn.resp_body)
      assert data["host"] == "host-a"
      assert length(data["endpoints"]) == 1
    end

    test "returns 404 when host has no endpoints" do
      conn = call(["hosts", "unknown"])
      assert conn.status == 404
    end
  end

  describe "GET /api/routes" do
    test "returns routes" do
      :ets.insert(:monitorex_inbound_routes, {"GET:/api/users", %{requests: 3, errors: 0, total_duration: 30.0, last_seen: 1000}})

      conn = call(["routes"])
      assert conn.status == 200
      assert %{"ok" => true, "data" => [route]} = Jason.decode!(conn.resp_body)
      assert route["method"] == "GET"
      assert route["path"] == "/api/users"
    end
  end

  describe "GET /api/consumers" do
    test "returns consumers" do
      :ets.insert(:monitorex_inbound_consumers, {"alice", %{requests: 5, errors: 0, total_duration: 50.0, last_seen: 1000}})

      conn = call(["consumers"])
      assert conn.status == 200
      assert %{"ok" => true, "data" => [consumer]} = Jason.decode!(conn.resp_body)
      assert consumer["consumer"] == "alice"
    end
  end

  describe "GET /api/events" do
    test "returns outbound events with pagination headers" do
      :ets.insert(:monitorex_outbound_recent, {1, %Event{timestamp: 1, method: "GET", host: "a", path: "/x", status: 200, status_class: :success}})

      conn = call(["events"])
      assert conn.status == 200
      assert {"x-total-count", "1"} in conn.resp_headers
      assert {"x-returned-count", "1"} in conn.resp_headers
    end

    test "filters by direction inbound" do
      :ets.insert(:monitorex_inbound_recent, {1, %Event{direction: :inbound, timestamp: 1, method: "GET", path: "/api", status: 200, status_class: :success, consumer: "alice"}})

      conn = call(["events"], %{"direction" => "inbound"})
      assert conn.status == 200
      assert %{"ok" => true, "data" => [event]} = Jason.decode!(conn.resp_body)
      assert event["direction"] == "inbound"
    end

    test "post-filters by method and status" do
      :ets.insert(:monitorex_outbound_recent, {1, %Event{timestamp: 1, method: "GET", host: "a", path: "/x", status: 200, status_class: :success}})
      :ets.insert(:monitorex_outbound_recent, {2, %Event{timestamp: 2, method: "POST", host: "a", path: "/y", status: 500, status_class: :server_error}})

      conn = call(["events"], %{"method" => "POST", "status" => "500"})
      assert conn.status == 200
      assert %{"ok" => true, "data" => [event]} = Jason.decode!(conn.resp_body)
      assert event["method"] == "POST"
      assert event["status"] == 500
    end

    test "post-filters by since" do
      now = System.system_time(:microsecond)
      :ets.insert(:monitorex_outbound_recent, {1, %Event{timestamp: now - 10_000_000, method: "GET", host: "a", path: "/x", status: 200, status_class: :success}})
      :ets.insert(:monitorex_outbound_recent, {2, %Event{timestamp: now, method: "GET", host: "a", path: "/y", status: 200, status_class: :success}})

      since = DateTime.to_iso8601(DateTime.from_unix!(div(now - 1_000_000, 1_000_000)))
      conn = call(["events"], %{"since" => since})
      assert conn.status == 200
      assert %{"ok" => true, "data" => [_]} = Jason.decode!(conn.resp_body)
    end
  end

  describe "GET /api/events/:timestamp" do
    test "returns event by timestamp" do
      event = %Event{timestamp: 123, method: "GET", host: "a", path: "/x", status: 200, status_class: :success}
      :ets.insert(:monitorex_outbound_recent, {123, event})

      conn = call(["events", "123"])
      assert conn.status == 200
      assert %{"ok" => true, "data" => %{"timestamp" => 123}} = Jason.decode!(conn.resp_body)
    end

    test "returns 404 for missing event" do
      conn = call(["events", "123"])
      assert conn.status == 404
    end

    test "returns 400 for invalid timestamp" do
      conn = call(["events", "abc"])
      assert conn.status == 400
    end
  end

  describe "GET /api/metrics" do
    test "returns aggregated metrics" do
      :ets.insert(:monitorex_outbound_hosts, {"host-a", %{requests: 10, errors: 1, total_duration: 100.0, last_seen: 1000, p50: 5.0, p95: 10.0, p99: 15.0}})

      conn = call(["metrics"])
      assert conn.status == 200
      assert %{"ok" => true, "data" => data} = Jason.decode!(conn.resp_body)
      assert data["hosts_count"] == 1
      assert data["total_requests"] == 10
    end

    test "filters metrics by host" do
      :ets.insert(:monitorex_outbound_hosts, {"host-a", %{requests: 10, errors: 1, total_duration: 100.0, last_seen: 1000}})
      :ets.insert(:monitorex_outbound_hosts, {"host-b", %{requests: 5, errors: 0, total_duration: 50.0, last_seen: 1000}})

      conn = call(["metrics"], %{"host" => "host-a"})
      assert conn.status == 200
      assert %{"ok" => true, "data" => data} = Jason.decode!(conn.resp_body)
      assert data["total_requests"] == 10
    end
  end

  describe "GET /api/health" do
    test "returns health JSON" do
      conn = call(["health"])
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["status"]
    end
  end

  describe "unknown routes and methods" do
    test "returns 404 for unknown route" do
      conn = call(["unknown"])
      assert conn.status == 404
    end

    test "returns 405 for non-GET/OPTIONS methods" do
      conn = call(["hosts"], %{}, :post)
      assert conn.status == 405
    end
  end
end
