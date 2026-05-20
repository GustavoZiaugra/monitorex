defmodule Monitorex.LoadTest do
  use ExUnit.Case, async: false

  alias Monitorex.Collector
  alias Monitorex.Event

  @moduledoc """
  Performance & load tests for the Monitorex data pipeline.

  These tests validate that the Collector's ring buffers, aggregate tables,
  and cleanup cycle handle high-throughput scenarios without unbounded growth
  or performance degradation.
  """

  # ── Cleanup helpers ──

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

  defp start_collector(name, opts \\ []) do
    {:ok, pid} = GenServer.start_link(Collector, opts, name: name)
    pid
  end

  defp await_cleanup(_pid, ms \\ 1000) do
    Process.sleep(ms)
  end

  # ── Helpers ──

  defp make_outbound(
         host \\ "loadtest.example.com",
         path \\ "/api/data",
         status \\ 200,
         duration \\ 50.0
       ) do
    %Event{
      source: :tesla,
      direction: :outbound,
      method: "GET",
      host: host,
      path: path,
      full_url: "https://#{host}#{path}",
      status: status,
      status_class: Event.classify_status(status),
      duration_ms: duration,
      timestamp: System.system_time(:second)
    }
  end

  defp make_inbound(method, path, status, duration, consumer) do
    %Event{
      source: :phoenix,
      direction: :inbound,
      method: method,
      host: "app.example.com",
      path: path,
      full_url: "https://app.example.com#{path}",
      status: status,
      status_class: Event.classify_status(status),
      duration_ms: duration,
      consumer: consumer,
      timestamp: System.system_time(:second)
    }
  end

  defp sample_ets_size(table) do
    case :ets.info(table, :size) do
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  # ────────────────────────────────────────────────────────
  # Ring buffer capping
  # ────────────────────────────────────────────────────────

  describe "ring buffer capping" do
    @describetag :load

    test "outbound_recent stays at max_recent under sustained load" do
      Application.put_env(:monitorex, :max_recent, 100)
      Application.put_env(:monitorex, :max_recent_inbound, 100)
      Application.put_env(:monitorex, :cleanup_interval_ms, 200)
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])

      pid = start_collector(:load_test_ring_cap)

      event = make_outbound()
      for _ <- 1..500, do: Collector.handle_event(event, pid)

      # Wait for cleanup to trim the ring buffer
      await_cleanup(pid, 600)

      recent_size = sample_ets_size(:monitorex_outbound_recent)
      hosts_size = sample_ets_size(:monitorex_outbound_hosts)

      assert recent_size <= 100,
             "outbound_recent should be capped at 100, got #{recent_size}"

      assert hosts_size == 1,
             "all events share the same host, so only 1 host aggregate expected"

      Application.delete_env(:monitorex, :max_recent)
      Application.delete_env(:monitorex, :max_recent_inbound)
      Application.delete_env(:monitorex, :cleanup_interval_ms)
    end

    test "inbound_recent stays at max_recent_inbound under sustained load" do
      Application.put_env(:monitorex, :max_recent_inbound, 50)
      Application.put_env(:monitorex, :cleanup_interval_ms, 200)
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])

      pid = start_collector(:load_test_ring_inbound)

      event = make_inbound("GET", "/api/test", 200, 50.0, nil)
      for _ <- 1..300, do: Collector.handle_event(event, pid)

      await_cleanup(pid, 600)

      recent_size = sample_ets_size(:monitorex_inbound_recent)

      assert recent_size <= 50,
             "inbound_recent should be capped at 50, got #{recent_size}"

      Application.delete_env(:monitorex, :max_recent_inbound)
      Application.delete_env(:monitorex, :cleanup_interval_ms)
    end
  end

  # ────────────────────────────────────────────────────────
  # Throughput benchmark
  # ────────────────────────────────────────────────────────

  describe "throughput" do
    @describetag :load

    test "handles 2,000 events within acceptable time" do
      Application.put_env(:monitorex, :max_recent, 500)
      Application.put_env(:monitorex, :max_recent_inbound, 500)
      Application.put_env(:monitorex, :cleanup_interval_ms, 10_000)
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])

      pid = start_collector(:load_test_throughput)
      n = 2_000
      hosts = for i <- 1..20, do: "host-#{i}.example.com"

      events =
        for i <- 1..n do
          host = Enum.at(hosts, rem(i, length(hosts)))
          path = "/api/#{rem(i, 10)}"
          status = Enum.random([200, 200, 200, 201, 204, 301, 400, 404, 500, 502])
          make_outbound(host, path, status, :rand.uniform(500) * 1.0)
        end

      {send_time, _count} =
        :timer.tc(fn ->
          Enum.reduce(events, 0, fn ev, c ->
            Collector.handle_event(ev, pid)
            c + 1
          end)
        end)

      send_ms = send_time / 1000
      rate = n / (send_ms / 1000)

      IO.puts(
        "\n    Throughput: #{Float.round(rate, 0)} events/sec (#{n} events in #{Float.round(send_ms, 1)} ms)"
      )

      assert send_ms < 10_000,
             "Sending #{n} events should take < 10s, took #{Float.round(send_ms, 1)}ms"

      Application.delete_env(:monitorex, :cleanup_interval_ms)
    end
  end

  # ────────────────────────────────────────────────────────
  # Aggregate table growth under high cardinality
  # ────────────────────────────────────────────────────────

  describe "aggregate table limits" do
    @describetag :load

    test "host aggregate table grows predictably with unique hosts" do
      Application.put_env(:monitorex, :max_recent, 500)
      Application.put_env(:monitorex, :cleanup_interval_ms, 200)
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])
      Application.put_env(:monitorex, :endpoint_ttl, :timer.hours(1))

      pid = start_collector(:load_test_cardinality)
      n = 1_000

      events =
        for i <- 1..n do
          host = "unique-#{String.pad_leading(Integer.to_string(i), 5, "0")}.example.com"
          make_outbound(host, "/api/data", 200, :rand.uniform(100) * 1.0)
        end

      Enum.each(events, &Collector.handle_event(&1, pid))

      # Wait for cleanup cycles to trim recent buffer (interval=200ms)
      await_cleanup(pid, 1000)

      host_count = sample_ets_size(:monitorex_outbound_hosts)
      recent_count = sample_ets_size(:monitorex_outbound_recent)

      # Recent buffer should cap at 500
      assert recent_count <= 500,
             "recent buffer exceeded max_recent: #{recent_count} > 500"

      # All unique hosts should be in the aggregate table
      assert host_count == n,
             "expected #{n} unique hosts, got #{host_count}"

      host_mem_words = :ets.info(:monitorex_outbound_hosts, :memory) || 0
      host_mem_bytes = host_mem_words * 8
      per_host = host_mem_bytes / n

      IO.puts(
        "\n    #{n} unique hosts → #{host_mem_words} words ETS (#{Float.round(host_mem_bytes / 1024, 1)} KB)"
      )

      IO.puts("    Per-host overhead: ~#{Float.round(per_host, 1)} bytes")

      Application.delete_env(:monitorex, :cleanup_interval_ms)
      Application.delete_env(:monitorex, :endpoint_ttl)
    end
  end

  # ────────────────────────────────────────────────────────
  # Cleanup performance
  # ────────────────────────────────────────────────────────

  describe "cleanup performance" do
    @describetag :load

    test "cleanup completes within acceptable time under load" do
      Application.put_env(:monitorex, :max_recent, 500)
      Application.put_env(:monitorex, :max_recent_inbound, 500)
      Application.put_env(:monitorex, :cleanup_interval_ms, 500)
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])

      pid = start_collector(:load_test_cleanup)

      # Send events to 50 unique hosts with 20 endpoints each
      events =
        for i <- 1..1000 do
          host = "cleanup-host-#{rem(i, 50)}.example.com"
          path = "/api/#{rem(i, 20)}"
          make_outbound(host, path, Enum.random([200, 404, 500]), :rand.uniform(200) * 1.0)
        end

      Enum.each(events, &Collector.handle_event(&1, pid))

      # Wait for at least 2 cleanup cycles
      await_cleanup(pid, 1500)

      host_count = sample_ets_size(:monitorex_outbound_hosts)
      recent_count = sample_ets_size(:monitorex_outbound_recent)
      endpoint_count = sample_ets_size(:monitorex_outbound_endpoints)

      IO.puts("\n    Hosts: #{host_count}, Endpoints: #{endpoint_count}, Recent: #{recent_count}")

      assert host_count > 0, "hosts should exist"
      assert recent_count <= 500, "recent buffer should be capped at 500"

      Application.delete_env(:monitorex, :cleanup_interval_ms)
    end
  end

  # ────────────────────────────────────────────────────────
  # Mixed direction throughput
  # ────────────────────────────────────────────────────────

  describe "mixed direction throughput" do
    @describetag :load

    test "handles concurrent inbound + outbound events without issues" do
      Application.put_env(:monitorex, :max_recent, 500)
      Application.put_env(:monitorex, :max_recent_inbound, 500)
      Application.put_env(:monitorex, :cleanup_interval_ms, 200)
      Application.put_env(:monitorex, :sources, [])
      Application.put_env(:monitorex, :clients, [])

      pid = start_collector(:load_test_mixed_dir)
      n = 2_000

      events =
        for i <- 1..n do
          if rem(i, 2) == 0 do
            make_outbound(
              "mix-host-#{rem(i, 30)}.com",
              "/api/#{rem(i, 10)}",
              Enum.random([200, 404, 500])
            )
          else
            make_inbound(
              Enum.random(["GET", "POST"]),
              "/api/v#{rem(i, 3)}/resource",
              Enum.random([200, 201, 400, 500]),
              30 + :rand.uniform(100),
              Enum.random([nil, "svc-a", "svc-b", "svc-c"])
            )
          end
        end

      {time_us, _} =
        :timer.tc(fn ->
          Enum.each(events, &Collector.handle_event(&1, pid))
        end)

      time_ms = time_us / 1000
      rate = n / (time_ms / 1000)

      IO.puts(
        "\n    Mixed throughput: #{Float.round(rate, 0)} events/sec (#{n} events in #{Float.round(time_ms, 1)}ms)"
      )

      # Wait for cleanup cycles to trim ring buffers
      await_cleanup(pid, 1000)

      out_recent = sample_ets_size(:monitorex_outbound_recent)
      in_recent = sample_ets_size(:monitorex_inbound_recent)
      hosts = sample_ets_size(:monitorex_outbound_hosts)
      routes = sample_ets_size(:monitorex_inbound_routes)

      IO.puts("    Outbound recent: #{out_recent}, Inbound recent: #{in_recent}")
      IO.puts("    Hosts: #{hosts}, Routes: #{routes}")

      assert out_recent <= 500
      assert in_recent <= 500

      Application.delete_env(:monitorex, :cleanup_interval_ms)
    end
  end
end
