defmodule Monitorex.IntegrationTest do
  use ExUnit.Case, async: false

  alias Monitorex.Collector
  alias Monitorex.EventHandler
  alias Monitorex.Storage
  alias Plug.Test

  # ── Setup: start isolated Collector per test ──

  setup do
    # Clean ETS tables from any previous runs
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

    # Start an isolated Collector with a unique name
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    name = :"collector_int_#{System.unique_integer([:positive])}"
    {:ok, pid} = GenServer.start_link(Collector, [], name: name)

    on_exit(fn ->
      # The isolated Collector's terminate/2 deletes the global ETS
      # tables (shared atom names). Recreate them so the application-
      # level Collector doesn't crash on its next cleanup cycle.
      table_specs = [
        {:monitorex_outbound_hosts, :set},
        {:monitorex_outbound_endpoints, :set},
        {:monitorex_outbound_recent, :ordered_set},
        {:monitorex_outbound_duration_samples, :bag},
        {:monitorex_inbound_routes, :set},
        {:monitorex_inbound_consumers, :set},
        {:monitorex_inbound_recent, :ordered_set},
        {:monitorex_inbound_duration_samples, :bag},
        {:monitorex_slow_outbound, :ordered_set},
        {:monitorex_slow_inbound, :ordered_set}
      ]

      Enum.each(table_specs, fn {table, type} ->
        try do
          :ets.new(table, [:public, :named_table, type, read_concurrency: true])
        rescue
          _ -> :ok
        end
      end)
    end)

    %{collector: pid, collector_name: name}
  end

  # ── Helper: wait for collector to process ──

  defp await_collector(pid) do
    _ = :sys.get_state(pid)
    Process.sleep(10)
  end

  # ── Tesla → Event → ETS → Storage ──

  describe "Tesla pipeline (outbound)" do
    test "full flow: telemetry metadata → Event → ETS → Storage.list_hosts", %{collector: pid} do
      url = %URI{scheme: "https", host: "api.example.com", path: "/users", query: nil}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          %{duration: 1_000_000},
          %{
            url: url,
            method: :get,
            status: 200,
            pid: self(),
            monotonic_time: System.monotonic_time()
          },
          []
        )

      Collector.handle_event(event, pid)
      await_collector(pid)

      hosts = Storage.list_hosts()
      assert length(hosts) == 1
      host = hd(hosts)
      assert host.host == "api.example.com"
      assert host.requests == 1
      assert host.errors == 0

      endpoints = Storage.list_endpoints_for_host("api.example.com")
      assert [endpoint] = endpoints
      assert endpoint.path == "/users"

      recent = Storage.list_recent_outbound()
      assert recent != []
    end

    test "multiple events increment counters", %{collector: pid} do
      url = %URI{scheme: "https", host: "api.example.com", path: "/users", query: nil}

      for _ <- 1..5 do
        event =
          EventHandler.handle_tesla_event(
            [:tesla, :request, :stop],
            %{duration: 1_000_000},
            %{
              url: url,
              method: :get,
              status: 200,
              pid: self(),
              monotonic_time: System.monotonic_time()
            },
            []
          )

        Collector.handle_event(event, pid)
      end

      await_collector(pid)

      hosts = Storage.list_hosts()
      assert hd(hosts).requests == 5
    end

    test "errors are counted separately", %{collector: pid} do
      url = %URI{scheme: "https", host: "api.example.com", path: "/error", query: nil}

      event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          %{duration: 500_000},
          %{
            url: url,
            method: :post,
            status: 500,
            pid: self(),
            monotonic_time: System.monotonic_time()
          },
          []
        )

      Collector.handle_event(event, pid)
      await_collector(pid)

      hosts = Storage.list_hosts()
      assert hd(hosts).requests == 1
      assert hd(hosts).errors == 1
    end
  end

  # ── Finch → Event → ETS → Storage ──

  describe "Finch pipeline (outbound)" do
    test "full flow: Finch telemetry → Event → ETS → Storage.list_hosts", %{collector: pid} do
      url = %URI{scheme: "https", host: "finch-api.example.com", path: "/v2/resource"}

      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          %{duration: 2_000_000},
          %{
            url: url,
            method: :get,
            status: 200,
            pid: self(),
            monotonic_time: System.monotonic_time()
          },
          []
        )

      Collector.handle_event(event, pid)
      await_collector(pid)

      hosts = Storage.list_hosts()
      assert [host] = hosts
      assert host.host == "finch-api.example.com"

      recent = Storage.list_recent_outbound()
      assert recent != []
    end

    test "Finch with string URL", %{collector: pid} do
      event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          %{duration: 1_500_000},
          %{
            url: "https://string.example.com/data",
            method: "POST",
            status: 201,
            pid: self(),
            monotonic_time: System.monotonic_time()
          },
          []
        )

      Collector.handle_event(event, pid)
      await_collector(pid)

      hosts = Storage.list_hosts()
      assert hd(hosts).host == "string.example.com"
    end
  end

  # ── Phoenix → Event → ETS → Storage ──

  describe "Phoenix pipeline (inbound)" do
    test "full flow with basic-auth consumer extraction", %{collector: pid} do
      base_conn = Test.conn(:get, "/api/v1/users", nil)

      conn =
        base_conn
        |> Map.put(:status, 200)
        |> Map.put(:host, "example.com")
        |> Map.put(:req_headers, [
          {"authorization", "Basic " <> Base.encode64("myapp-web:secret")}
        ])

      event =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          %{duration: 3_000_000},
          %{conn: conn},
          []
        )

      assert event != nil
      assert event.consumer == "myapp-web"

      Collector.handle_event(event, pid)
      await_collector(pid)

      routes = Storage.list_routes()
      route = Enum.find(routes, &(&1.method == "GET" and &1.path == "/api/v1/users"))
      assert route != nil
      assert route.requests == 1

      consumers = Storage.list_consumers()
      consumer = Enum.find(consumers, &(&1.consumer == "myapp-web"))
      assert consumer != nil
      assert consumer.requests == 1

      recent = Storage.list_recent_inbound()
      assert recent != []
    end
  end

  # ── Dedup flow ──

  describe "dedup flow" do
    setup do
      Application.put_env(:monitorex, :clients, [:tesla, :finch])

      # Clean all ETS tables before starting dedup collector
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

      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      name = :"collector_dedup_#{System.unique_integer([:positive])}"
      {:ok, pid} = GenServer.start_link(Collector, [], name: name)
      {:ok, %{collector: pid}}
    end

    test "same event from tesla and finch is only stored once", %{collector: pid} do
      url = %URI{scheme: "https", host: "dedup-test.com", path: "/data"}
      mono = System.monotonic_time()

      tesla_event =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          %{duration: 100_000},
          %{url: url, method: :get, status: 200, pid: self(), monotonic_time: mono},
          []
        )

      finch_event =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          %{duration: 100_000},
          %{url: url, method: :get, status: 200, pid: self(), monotonic_time: mono},
          []
        )

      assert tesla_event.dedup_key == finch_event.dedup_key

      Collector.handle_event(tesla_event, pid)
      Collector.handle_event(finch_event, pid)
      await_collector(pid)

      hosts = Storage.list_hosts()
      host = Enum.find(hosts, &(&1.host == "dedup-test.com"))
      assert host != nil
      assert host.requests == 1, "Expected dedup to prevent double-counting"
    end

    test "different events are both stored", %{collector: pid} do
      mono1 = System.monotonic_time()
      mono2 = System.monotonic_time() + 100

      e1 =
        EventHandler.handle_tesla_event(
          [:tesla, :request, :stop],
          %{duration: 100_000},
          %{
            url: %URI{host: "a.com", path: "/x"},
            method: :get,
            status: 200,
            pid: self(),
            monotonic_time: mono1
          },
          []
        )

      e2 =
        EventHandler.handle_finch_event(
          [:finch, :request, :stop],
          %{duration: 200_000},
          %{
            url: %URI{host: "b.com", path: "/y"},
            method: :post,
            status: 201,
            pid: self(),
            monotonic_time: mono2
          },
          []
        )

      Collector.handle_event(e1, pid)
      Collector.handle_event(e2, pid)
      await_collector(pid)

      assert length(Storage.list_hosts()) == 2
    end
  end

  # ── Filter flow (inbound_path_prefixes) ──

  describe "filter flow" do
    test "phoenix event outside inbound_path_prefixes is not stored", %{collector: pid} do
      Application.put_env(:monitorex, :inbound_path_prefixes, ["/api"])

      base_conn_in = Test.conn(:get, "/api/v1/products", nil)
      conn_in = base_conn_in |> Map.put(:status, 200) |> Map.put(:host, "example.com")

      event_in =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          %{duration: 1_000_000},
          %{conn: conn_in},
          []
        )

      assert event_in != nil
      Collector.handle_event(event_in, pid)

      base_conn_out = Test.conn(:get, "/health", nil)
      conn_out = base_conn_out |> Map.put(:status, 200) |> Map.put(:host, "example.com")

      event_out =
        EventHandler.handle_phoenix_event(
          [:phoenix, :router_dispatch, :stop],
          %{duration: 1_000_000},
          %{conn: conn_out},
          []
        )

      assert event_out == nil

      await_collector(pid)

      routes = Storage.list_routes()
      assert length(routes) == 1
      assert hd(routes).path == "/api/v1/products"

      Application.delete_env(:monitorex, :inbound_path_prefixes)
    end
  end
end
