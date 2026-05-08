defmodule Monitorex.CollectorTest do
  use ExUnit.Case, async: false

  alias Monitorex.Collector
  alias Monitorex.Event

  setup do
    # Clean up any leftover ETS tables from previous runs
    Enum.each(
      [
        :monitorex_outbound_hosts,
        :monitorex_outbound_endpoints,
        :monitorex_outbound_recent,
        :monitorex_outbound_duration_samples,
        :monitorex_inbound_routes,
        :monitorex_inbound_consumers,
        :monitorex_inbound_recent,
        :monitorex_inbound_duration_samples,
        :monitorex_dedup
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

  describe "start_link/1" do
    test "starts and creates all ETS tables" do
      # Use a unique name to avoid conflicts
      name = :"collector_start_#{System.unique_integer([:positive])}"
      {:ok, pid} = GenServer.start_link(Collector, [], name: name)

      assert :ets.info(:monitorex_outbound_hosts)[:name] == :monitorex_outbound_hosts
      assert :ets.info(:monitorex_outbound_endpoints)[:name] == :monitorex_outbound_endpoints
      assert :ets.info(:monitorex_outbound_recent)[:name] == :monitorex_outbound_recent

      assert :ets.info(:monitorex_outbound_duration_samples)[:name] ==
               :monitorex_outbound_duration_samples

      assert :ets.info(:monitorex_inbound_routes)[:name] == :monitorex_inbound_routes
      assert :ets.info(:monitorex_inbound_consumers)[:name] == :monitorex_inbound_consumers
      assert :ets.info(:monitorex_inbound_recent)[:name] == :monitorex_inbound_recent

      assert :ets.info(:monitorex_inbound_duration_samples)[:name] ==
               :monitorex_inbound_duration_samples

      GenServer.stop(pid)
    end

    test "creates dedup table when both tesla and finch in clients config" do
      Application.put_env(:monitorex, :clients, [:tesla, :finch])

      name = :"collector_dedup_#{System.unique_integer([:positive])}"
      {:ok, pid} = GenServer.start_link(Collector, [], name: name)

      assert :ets.info(:monitorex_dedup)[:name] == :monitorex_dedup

      Application.delete_env(:monitorex, :clients)
      GenServer.stop(pid)
    end
  end

  describe "handle_event/1 — outbound" do
    setup do
      name = :"collector_outbound_#{System.unique_integer([:positive])}"
      {:ok, pid} = GenServer.start_link(Collector, [], name: name)
      %{pid: pid}
    end

    test "writes outbound event to host aggregate", %{pid: pid} do
      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/users/:id",
        status: 200,
        duration_ms: 45.0
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      host = event.host
      assert [{^host, agg}] = :ets.lookup(:monitorex_outbound_hosts, "api.example.com")
      assert agg.requests == 1
      assert agg.errors == 0
    end

    test "writes outbound event to endpoint aggregate", %{pid: pid} do
      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/users/:id",
        status: 200,
        duration_ms: 45.0
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      key = {"api.example.com", "/users/:id"}
      assert [{^key, agg}] = :ets.lookup(:monitorex_outbound_endpoints, key)
      assert agg.requests == 1
    end

    test "writes outbound event to recent ring buffer", %{pid: pid} do
      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/users/:id",
        status: 200,
        duration_ms: 45.0
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      assert :ets.info(:monitorex_outbound_recent, :size) == 1
    end

    test "writes duration sample", %{pid: pid} do
      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/users/:id",
        status: 200,
        duration_ms: 45.0
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      samples = :ets.lookup(:monitorex_outbound_duration_samples, "api.example.com")
      assert length(samples) == 1
    end

    test "increments request count on duplicate host", %{pid: pid} do
      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/users/:id",
        status: 200,
        duration_ms: 10.0
      }

      Collector.handle_event(event, pid)
      Collector.handle_event(event, pid)
      Process.sleep(50)

      assert [{_, agg}] = :ets.lookup(:monitorex_outbound_hosts, "api.example.com")
      assert agg.requests == 2
    end
  end

  describe "handle_event/1 — inbound" do
    setup do
      name = :"collector_inbound_#{System.unique_integer([:positive])}"
      {:ok, pid} = GenServer.start_link(Collector, [], name: name)
      %{pid: pid}
    end

    test "writes inbound event to route aggregate", %{pid: pid} do
      event = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/api/orders",
        status: 200,
        duration_ms: 20.0,
        consumer: "alice"
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      route_key = "GET:/api/orders"
      assert [{^route_key, agg}] = :ets.lookup(:monitorex_inbound_routes, route_key)
      assert agg.requests == 1
    end

    test "writes inbound event to consumer aggregate", %{pid: pid} do
      event = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "POST",
        path: "/api/orders",
        status: 201,
        duration_ms: 15.0,
        consumer: "alice"
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      assert [{_, agg}] = :ets.lookup(:monitorex_inbound_consumers, "alice")
      assert agg.requests == 1
    end

    test "handles inbound event with nil consumer", %{pid: pid} do
      event = %Event{
        source: :phoenix,
        direction: :inbound,
        method: "GET",
        path: "/health",
        status: 200,
        duration_ms: 1.0,
        consumer: nil
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      assert :ets.info(:monitorex_inbound_consumers, :size) == 0
    end

    test "truncates request and response bodies exceeding max_body_bytes", %{pid: pid} do
      Application.put_env(:monitorex, :max_body_bytes, 5)

      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "POST",
        host: "api.example.com",
        path: "/upload",
        status: 200,
        duration_ms: 10.0,
        request_body: "1234567890",
        response_body: "abcdefghij"
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      [{_, stored}] =
        :ets.lookup(:monitorex_outbound_recent, :ets.first(:monitorex_outbound_recent))

      assert stored.request_body == "12345"
      assert stored.response_body == "abcde"

      Application.delete_env(:monitorex, :max_body_bytes)
    end

    test "does not truncate bodies under max_body_bytes", %{pid: pid} do
      Application.put_env(:monitorex, :max_body_bytes, 100)

      event = %Event{
        source: :tesla,
        direction: :outbound,
        method: "GET",
        host: "api.example.com",
        path: "/small",
        status: 200,
        duration_ms: 10.0,
        request_body: "tiny",
        response_body: nil
      }

      Collector.handle_event(event, pid)
      Process.sleep(50)

      [{_, stored}] =
        :ets.lookup(:monitorex_outbound_recent, :ets.first(:monitorex_outbound_recent))

      assert stored.request_body == "tiny"
      assert stored.response_body == nil

      Application.delete_env(:monitorex, :max_body_bytes)
    end
  end
end
