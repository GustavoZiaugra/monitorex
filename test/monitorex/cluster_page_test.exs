defmodule Monitorex.ClusterPageTest do
  use ExUnit.Case, async: false
  import Monitorex.LiveComponentFixtures

  alias Monitorex.ClusterPage

  setup do
    Application.put_env(:monitorex, :cluster_mode, :single)
    on_exit(fn -> Application.delete_env(:monitorex, :cluster_mode) end)
    reset_ets_tables()
    :ok
  end

  describe "list_hosts/0" do
    test "returns local hosts when cluster_mode is :single" do
      result = ClusterPage.list_hosts()
      assert is_list(result)
    end

    test "returns local hosts when cluster_mode is :auto but only one node" do
      Application.put_env(:monitorex, :cluster_mode, :auto)
      result = ClusterPage.list_hosts()
      assert is_list(result)
    end

    test "returns empty list when no ETS tables exist" do
      result = ClusterPage.list_hosts()
      assert result == []
    end

    test "returns hosts with real data" do
      insert_outbound_event(host: "api.example.com", method: "GET", path: "/users")

      [host] = ClusterPage.list_hosts()
      assert host.host == "api.example.com"
      assert host.requests == 1
    end
  end

  describe "list_routes/0" do
    test "returns local routes when cluster_mode is :single" do
      result = ClusterPage.list_routes()
      assert is_list(result)
      assert result == []
    end

    test "returns routes with real data" do
      insert_inbound_event(method: "GET", path: "/api/items")

      [route] = ClusterPage.list_routes()
      assert route.method == "GET"
      assert route.path == "/api/items"
    end
  end

  describe "list_consumers/0" do
    test "returns local consumers when cluster_mode is :single" do
      result = ClusterPage.list_consumers()
      assert is_list(result)
      assert result == []
    end

    test "returns consumers with real data" do
      insert_inbound_event(consumer: "svc-a")

      [consumer] = ClusterPage.list_consumers()
      assert consumer.consumer == "svc-a"
    end
  end

  describe "list_endpoints_for_host/1" do
    test "returns local endpoints when cluster_mode is :single" do
      result = ClusterPage.list_endpoints_for_host("example.com")
      assert is_list(result)
      assert result == []
    end

    test "returns endpoints with real data" do
      insert_outbound_event(host: "api.example.com", method: "GET", path: "/users")

      [endpoint] = ClusterPage.list_endpoints_for_host("api.example.com")
      assert endpoint.path == "/users"
    end
  end

  describe "list_recent_outbound/1" do
    test "returns local recent outbound when cluster_mode is :single" do
      result = ClusterPage.list_recent_outbound()
      assert is_list(result)
      assert result == []
    end

    test "passes keyword options through to Storage" do
      result = ClusterPage.list_recent_outbound(host: "example.com", limit: 10)
      assert is_list(result)
    end

    test "returns recent outbound events with real data" do
      insert_outbound_event(method: "GET", path: "/users")

      [event] = ClusterPage.list_recent_outbound()
      assert event.method == "GET"
      assert event.path == "/users"
    end
  end

  describe "list_recent_inbound/1" do
    test "returns local recent inbound when cluster_mode is :single" do
      result = ClusterPage.list_recent_inbound()
      assert is_list(result)
      assert result == []
    end

    test "passes keyword options through to Storage" do
      result = ClusterPage.list_recent_inbound(consumer: "test", limit: 10)
      assert is_list(result)
    end

    test "returns recent inbound events with real data" do
      insert_inbound_event(method: "POST", path: "/api/orders", consumer: "svc-b")

      [event] = ClusterPage.list_recent_inbound()
      assert event.method == "POST"
      assert event.consumer == "svc-b"
    end
  end

  describe "count_recent_outbound/1" do
    test "returns empty when no data" do
      result = ClusterPage.count_recent_outbound()
      assert result == [] or result == 0
    end

    test "passes keyword options through" do
      result = ClusterPage.count_recent_outbound(host: "example.com")
      assert result == [] or result == 0
    end

    test "returns count with real data" do
      insert_outbound_event(method: "GET", path: "/users")
      assert ClusterPage.count_recent_outbound() == 1
    end
  end

  describe "count_recent_inbound/1" do
    test "returns empty when no data" do
      result = ClusterPage.count_recent_inbound()
      assert result == [] or result == 0
    end

    test "passes keyword options through" do
      result = ClusterPage.count_recent_inbound(consumer: "test")
      assert result == [] or result == 0
    end

    test "returns count with real data" do
      insert_inbound_event(method: "POST", path: "/api/orders")
      assert ClusterPage.count_recent_inbound() == 1
    end
  end

  describe "list_consumers_for_route/1" do
    test "returns local consumers for route when cluster_mode is :single" do
      result = ClusterPage.list_consumers_for_route("GET:/api/test")
      assert is_list(result)
      assert result == []
    end

    test "returns consumers for route with real data" do
      insert_inbound_event(method: "GET", path: "/api/items", consumer: "svc-a")

      [consumer] = ClusterPage.list_consumers_for_route("GET:/api/items")
      assert consumer.consumer == "svc-a"
    end
  end

  describe "cluster_mode behavior" do
    test "uses Storage directly when cluster_mode is :single" do
      Application.put_env(:monitorex, :cluster_mode, :single)
      assert ClusterPage.list_hosts() == []
    end

    test "still works in :auto mode with only local node" do
      Application.put_env(:monitorex, :cluster_mode, :auto)
      assert is_list(ClusterPage.list_hosts())
    end

    test "still works in :cluster mode with only local node" do
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      assert is_list(ClusterPage.list_hosts())
    end
  end

  describe "cluster mode with mocked nodes" do
    setup do
      on_exit(fn ->
        try do
          :meck.unload(Monitorex.Cluster)
        catch
          _, _ -> :ok
        end
      end)

      :ok
    end

    defp mock_cluster do
      try do
        :meck.unload(Monitorex.Cluster)
      catch
        _, _ -> :ok
      end

      :meck.new(Monitorex.Cluster, [:unstick, :passthrough])
    end

    test "list_hosts merges node results in cluster mode" do
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      mock_cluster()

      :meck.expect(Monitorex.Cluster, :fetch_from_all_nodes, fn :list_hosts, [] ->
        [%{host: "node-a.com", requests: 5}, %{host: "node-b.com", requests: 3}]
      end)

      :meck.expect(Monitorex.Cluster, :merge_hosts, fn hosts -> hosts end)

      hosts = ClusterPage.list_hosts()
      assert length(hosts) == 2
    end

    test "list_routes merges node results in cluster mode" do
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      mock_cluster()

      :meck.expect(Monitorex.Cluster, :fetch_from_all_nodes, fn :list_routes, [] ->
        [%{method: "GET", path: "/api"}]
      end)

      :meck.expect(Monitorex.Cluster, :merge_routes, fn routes -> routes end)

      routes = ClusterPage.list_routes()
      assert length(routes) == 1
    end

    test "list_consumers merges node results in cluster mode" do
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      mock_cluster()

      :meck.expect(Monitorex.Cluster, :fetch_from_all_nodes, fn :list_consumers, [] ->
        [%{consumer: "svc-a"}]
      end)

      :meck.expect(Monitorex.Cluster, :merge_consumers, fn consumers -> consumers end)

      consumers = ClusterPage.list_consumers()
      assert length(consumers) == 1
    end

    test "list_recent_outbound merges node results in cluster mode" do
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      mock_cluster()

      :meck.expect(Monitorex.Cluster, :fetch_from_all_nodes, fn :list_recent_outbound, [_opts] ->
        [%{method: "GET"}]
      end)

      :meck.expect(Monitorex.Cluster, :merge_recent, fn events, _limit -> events end)

      events = ClusterPage.list_recent_outbound(limit: 10)
      assert length(events) == 1
    end

    test "count_recent_outbound sums node results in cluster mode" do
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      mock_cluster()

      :meck.expect(Monitorex.Cluster, :fetch_from_all_nodes, fn :count_recent_outbound, [_opts] ->
        [node_a: 5, node_b: 3]
      end)

      assert ClusterPage.count_recent_outbound() == 8
    end
  end
end
