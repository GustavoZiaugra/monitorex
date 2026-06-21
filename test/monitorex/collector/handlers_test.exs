defmodule Monitorex.Collector.HandlersTest do
  use ExUnit.Case, async: false

  alias Monitorex.Collector
  alias Monitorex.Collector.Handlers
  alias Monitorex.Storage

  defp wait_for(fun, timeout_ms \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Enum.reduce_while(1..200, [], fn _, _ ->
      result = fun.()

      if result != [] or System.monotonic_time(:millisecond) >= deadline do
        {:halt, result}
      else
        Process.sleep(10)
        {:cont, []}
      end
    end)
  end

  @tables [
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
  ]

  setup do
    # Ensure a Collector is running to process handle_event casts.
    pid =
      case Process.whereis(Collector) do
        nil ->
          {:ok, pid} = Collector.start_link([])
          pid

        pid ->
          pid
      end

    # Ensure all required tables exist and are empty between tests.
    ensure_table(:monitorex_outbound_hosts, :set)
    ensure_table(:monitorex_outbound_endpoints, :set)
    ensure_table(:monitorex_outbound_recent, :ordered_set)
    ensure_table(:monitorex_outbound_duration_samples, :bag)
    ensure_table(:monitorex_inbound_routes, :set)
    ensure_table(:monitorex_inbound_consumers, :set)
    ensure_table(:monitorex_inbound_recent, :ordered_set)
    ensure_table(:monitorex_inbound_duration_samples, :bag)
    ensure_table(:monitorex_slow_outbound, :ordered_set)
    ensure_table(:monitorex_slow_inbound, :ordered_set)
    ensure_table(:monitorex_dedup, :set)

    Enum.each(@tables, fn table ->
      try do
        :ets.delete_all_objects(table)
      rescue
        _ -> :ok
      end
    end)

    {:ok, collector: pid}
  end

  defp ensure_table(name, type) do
    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:public, :named_table, type, read_concurrency: true])

      _ ->
        :ok
    end
  end

  describe "tesla/4" do
    test "handles stop event and forwards to collector" do
      url = %URI{scheme: "https", host: "api.example.com", path: "/users"}

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.tesla([:tesla, :request, :stop], measurements, metadata, [])

      hosts = wait_for(&Storage.list_hosts/0)
      assert length(hosts) == 1
      assert hd(hosts).host == "api.example.com"
    end

    test "handles exception event" do
      url = %URI{scheme: "https", host: "api.example.com", path: "/fail"}

      metadata = %{
        url: url,
        method: :get,
        pid: self(),
        monotonic_time: System.monotonic_time(),
        reason: :timeout
      }

      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.tesla([:tesla, :request, :exception], measurements, metadata, [])

      hosts = wait_for(&Storage.list_hosts/0)
      assert length(hosts) == 1
      assert hd(hosts).host == "api.example.com"
    end

    test "ignores unexpected tesla events" do
      assert Handlers.tesla([:tesla, :request, :start], %{}, %{}, []) == :ok
      assert Storage.list_hosts() == []
    end
  end

  describe "finch/4" do
    test "ignores unexpected finch events" do
      assert Handlers.finch([:finch, :request, :start], %{}, %{}, []) == :ok
      assert Storage.list_hosts() == []
    end

    test "handles stop event and forwards to collector" do
      metadata = %{
        url: "https://finch.example.com/data",
        method: :get,
        status: 200,
        pid: self(),
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.finch([:finch, :request, :stop], measurements, metadata, [])

      hosts = wait_for(&Storage.list_hosts/0)
      assert length(hosts) == 1
      assert hd(hosts).host == "finch.example.com"
    end

    test "handles exception event" do
      request = %{
        scheme: :https,
        host: "finch.example.com",
        port: 443,
        method: "GET",
        path: "/fail",
        headers: [],
        body: nil,
        query: nil
      }

      metadata = %{
        request: request,
        result: {:error, :timeout}
      }

      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.finch([:finch, :request, :exception], measurements, metadata, [])

      hosts = wait_for(&Storage.list_hosts/0)
      assert length(hosts) == 1
      assert hd(hosts).host == "finch.example.com"
    end
  end

  describe "req/4" do
    test "ignores unexpected req events" do
      assert Handlers.req([:req, :request, :pipeline, :start], %{}, %{}, []) == :ok
      assert Storage.list_hosts() == []
    end

    test "handles stop event and forwards to collector" do
      url = URI.parse("https://req.example.com/data")

      metadata = %{
        url: url,
        method: :get,
        status: 200,
        resp_headers: %{},
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.req([:req, :request, :pipeline, :stop], measurements, metadata, [])

      hosts = wait_for(&Storage.list_hosts/0)
      assert length(hosts) == 1
      assert hd(hosts).host == "req.example.com"
    end

    test "handles error event" do
      url = URI.parse("https://req.example.com/fail")

      metadata = %{
        url: url,
        method: :get,
        headers: [],
        error: %RuntimeError{message: "timeout"},
        monotonic_time: System.monotonic_time()
      }

      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.req([:req, :request, :pipeline, :error], measurements, metadata, [])

      hosts = wait_for(&Storage.list_hosts/0)
      assert length(hosts) == 1
      assert hd(hosts).host == "req.example.com"
    end
  end

  describe "phoenix/4" do
    test "ignores unexpected phoenix events" do
      assert Handlers.phoenix([:phoenix, :router_dispatch, :start], %{}, %{}, []) == :ok
      assert Storage.list_routes() == []
    end

    test "handles stop event and forwards to collector" do
      base_conn = Plug.Test.conn(:get, "/api/users", nil)
      conn = base_conn |> Map.put(:status, 200) |> Map.put(:host, "example.com")

      metadata = %{conn: conn}
      measurements = %{duration: 1_000_000}

      assert :ok = Handlers.phoenix([:phoenix, :router_dispatch, :stop], measurements, metadata, [])

      routes = wait_for(&Storage.list_routes/0)
      assert length(routes) == 1
      assert hd(routes).path == "/api/users"
    end
  end
end
