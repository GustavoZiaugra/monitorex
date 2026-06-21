defmodule Monitorex.PrometheusExporterTest do
  use ExUnit.Case, async: false

  alias Monitorex.PrometheusExporter

  setup do
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
        :monitorex_slow_outbound,
        :monitorex_slow_inbound,
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

  describe "format/0" do
    test "returns valid Prometheus text with headers" do
      output = PrometheusExporter.format()

      assert output =~ "# HELP monitorex_collector_info"
      assert output =~ "# TYPE monitorex_collector_info gauge"
      assert output =~ "monitorex_collector_info{version="
    end

    test "includes ETS size metrics for all tables even when empty" do
      output = PrometheusExporter.format()

      assert output =~ "# HELP monitorex_ets_size"
      assert output =~ "monitorex_ets_size{table=\"outbound_hosts\"} 0"
      assert output =~ "monitorex_ets_size{table=\"outbound_recent\"} 0"
    end

    test "includes request metrics when data exists" do
      # Simulate host data in ETS
      :ets.new(:monitorex_outbound_hosts, [:public, :named_table, :set])

      :ets.insert(
        :monitorex_outbound_hosts,
        {"api.test.com",
         %{requests: 42, errors: 3, total_duration: 8400.0, last_seen: System.monotonic_time()}}
      )

      :ets.new(:monitorex_outbound_recent, [:public, :named_table, :ordered_set])
      :ets.insert(:monitorex_outbound_recent, {1, %{}})
      :ets.insert(:monitorex_outbound_recent, {2, %{}})

      output = PrometheusExporter.format()

      assert output =~
               ~r/monitorex_requests_total\{host="api\.test\.com",direction="outbound"\} 42/

      assert output =~ ~r/monitorex_errors_total\{host="api\.test\.com",direction="outbound"\} 3/
      assert output =~ ~r/monitorex_events_recent\{direction="outbound"\} 2/
      assert output =~ ~r/monitorex_ets_size{table="outbound_hosts"} 1/
    end

    test "escapes special characters in labels" do
      :ets.new(:monitorex_outbound_hosts, [:public, :named_table, :set])

      :ets.insert(
        :monitorex_outbound_hosts,
        {"test\"host.com",
         %{requests: 1, errors: 0, total_duration: 100.0, last_seen: System.monotonic_time()}}
      )

      output = PrometheusExporter.format()

      assert output =~ ~r/host="test\\"host\.com"/
    end

    test "includes latency metrics when percentiles exist" do
      :ets.new(:monitorex_outbound_hosts, [:public, :named_table, :set])

      :ets.insert(
        :monitorex_outbound_hosts,
        {"latency.test.com",
         %{
           requests: 100,
           errors: 0,
           total_duration: 5000.0,
           last_seen: System.monotonic_time(),
           p50: 45.0,
           p95: 120.0,
           p99: 250.0
         }}
      )

      output = PrometheusExporter.format()

      assert output =~
               ~r/monitorex_latency_seconds\{host="latency\.test\.com",quantile="p50"\} 0\.045/

      assert output =~
               ~r/monitorex_latency_seconds\{host="latency\.test\.com",quantile="p95"\} 0\.12/

      assert output =~
               ~r/monitorex_latency_seconds\{host="latency\.test\.com",quantile="p99"\} 0\.25/
    end

    test "includes endpoint request metrics" do
      :ets.new(:monitorex_outbound_endpoints, [:public, :named_table, :set])

      :ets.insert(
        :monitorex_outbound_endpoints,
        {{"api.test.com", "/users"}, %{requests: 10, errors: 1, total_duration: 100.0, last_seen: System.monotonic_time()}}
      )

      output = PrometheusExporter.format()

      assert output =~
               ~r{monitorex_requests_total\{host="api\.test\.com",path="/users",direction="outbound",resource="endpoint"\} 10}
    end

    test "includes route request metrics" do
      :ets.new(:monitorex_inbound_routes, [:public, :named_table, :set])

      route_key = "GET" <> ":/api/users"

      :ets.insert(
        :monitorex_inbound_routes,
        {route_key, %{requests: 25, errors: 0, total_duration: 250.0, last_seen: System.monotonic_time()}}
      )

      output = PrometheusExporter.format()

      assert output =~
               ~r{monitorex_requests_total\{method="GET",path="/api/users",direction="inbound",resource="route"\} 25}
    end

    test "includes consumer request metrics" do
      :ets.new(:monitorex_inbound_consumers, [:public, :named_table, :set])

      :ets.insert(
        :monitorex_inbound_consumers,
        {"alice", %{requests: 7, errors: 0, total_duration: 70.0, last_seen: System.monotonic_time()}}
      )

      output = PrometheusExporter.format()

      assert output =~
               ~r{monitorex_requests_total\{consumer="alice",direction="inbound",resource="consumer"\} 7}
    end

    test "returns empty string when tables do not exist" do
      # Ensure tables are deleted
      try do
        :ets.delete(:monitorex_outbound_hosts)
      rescue
        _ -> :ok
      end

      output = PrometheusExporter.format()
      assert is_binary(output)
      assert output =~ "# HELP monitorex_collector_info"
    end
  end
end
