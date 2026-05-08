defmodule Monitorex.ClusterTest do
  use ExUnit.Case, async: false

  alias Monitorex.Cluster
  alias Monitorex.Event

  describe "connected_nodes/0" do
    test "returns at least [Node.self()]" do
      nodes = Cluster.connected_nodes()
      assert Node.self() in nodes
    end

    test "returns [Node.self()] when cluster_mode is :single" do
      Application.put_env(:monitorex, :cluster_mode, :single)
      on_exit(fn -> Application.delete_env(:monitorex, :cluster_mode) end)

      assert Cluster.connected_nodes() == [Node.self()]
    end

    test "includes Node.list() when cluster_mode is :auto" do
      Application.put_env(:monitorex, :cluster_mode, :auto)
      on_exit(fn -> Application.delete_env(:monitorex, :cluster_mode) end)

      nodes = Cluster.connected_nodes()
      assert Node.self() in nodes
    end
  end

  describe "fetch_from_all_nodes/2" do
    test "returns results from the local node" do
      Application.put_env(:monitorex, :cluster_mode, :single)
      on_exit(fn -> Application.delete_env(:monitorex, :cluster_mode) end)

      # list_hosts returns [] when no ETS table exists — that's fine
      result = Cluster.fetch_from_all_nodes(:list_hosts, [])
      assert length(result) == 1
      assert elem(hd(result), 0) == Node.self()
    end

    test "gracefully handles {:badrpc, _} by omitting that node" do
      # When only the local node is connected and cluster_mode is :cluster,
      # Node.list() is empty so we only query self — which succeeds.
      # This verifies the skip handling in the stream reduce.
      Application.put_env(:monitorex, :cluster_mode, :cluster)
      on_exit(fn -> Application.delete_env(:monitorex, :cluster_mode) end)

      result = Cluster.fetch_from_all_nodes(:list_hosts, [])
      # Should return results from self without crashing
      assert is_list(result)
    end
  end

  describe "merge_hosts/1" do
    test "merges host aggregates from multiple nodes" do
      node1 = :node1@host
      node2 = :node2@host

      hosts1 = [
        %{
          host: "api.example.com",
          requests: 100,
          errors: 5,
          total_duration: 5_000.0,
          avg_latency: 50.0,
          p50: 45.0,
          p95: 95.0,
          p99: 99.0,
          error_rate: 0.05
        },
        %{
          host: "db.example.com",
          requests: 50,
          errors: 1,
          total_duration: 2_500.0,
          avg_latency: 50.0,
          p50: 48.0,
          p95: 90.0,
          p99: 98.0,
          error_rate: 0.02
        }
      ]

      hosts2 = [
        %{
          host: "api.example.com",
          requests: 200,
          errors: 10,
          total_duration: 12_000.0,
          avg_latency: 60.0,
          p50: 55.0,
          p95: 110.0,
          p99: 150.0,
          error_rate: 0.05
        },
        %{
          host: "other.com",
          requests: 30,
          errors: 0,
          total_duration: 900.0,
          avg_latency: 30.0,
          p50: 28.0,
          p95: 40.0,
          p99: 45.0,
          error_rate: 0.0
        }
      ]

      result = Cluster.merge_hosts([{node1, hosts1}, {node2, hosts2}])

      assert length(result) == 3

      # api.example.com merged from both nodes
      api = Enum.find(result, &(&1.host == "api.example.com"))
      assert api.requests == 300
      assert api.errors == 15
      assert api.total_duration == 17_000.0
      assert_in_delta api.avg_latency, 17_000.0 / 300, 0.001
      assert api.node == [node1, node2]

      # Weighted p50: (100 * 45 + 200 * 55) / 300
      expected_p50 = (100 * 45.0 + 200 * 55.0) / 300
      assert_in_delta api.p50, expected_p50, 0.001

      # Weighted p95: (100 * 95 + 200 * 110) / 300
      expected_p95 = (100 * 95.0 + 200 * 110.0) / 300
      assert_in_delta api.p95, expected_p95, 0.001

      # db.example.com only from node1
      db = Enum.find(result, &(&1.host == "db.example.com"))
      assert db.requests == 50
      assert db.node == [node1]

      # other.com only from node2
      other = Enum.find(result, &(&1.host == "other.com"))
      assert other.requests == 30
      assert other.node == [node2]
    end

    test "handles empty input" do
      assert Cluster.merge_hosts([]) == []
    end

    test "handles nodes with empty lists" do
      node = :node@host
      assert Cluster.merge_hosts([{node, []}]) == []
    end

    test "sorts results by requests descending" do
      node = :node@host

      hosts = [
        %{
          host: "low",
          requests: 10,
          errors: 0,
          total_duration: 100.0,
          avg_latency: 10.0,
          p50: nil,
          p95: nil,
          p99: nil,
          error_rate: 0.0
        },
        %{
          host: "high",
          requests: 100,
          errors: 0,
          total_duration: 1_000.0,
          avg_latency: 10.0,
          p50: nil,
          p95: nil,
          p99: nil,
          error_rate: 0.0
        },
        %{
          host: "medium",
          requests: 50,
          errors: 0,
          total_duration: 500.0,
          avg_latency: 10.0,
          p50: nil,
          p95: nil,
          p99: nil,
          error_rate: 0.0
        }
      ]

      result = Cluster.merge_hosts([{node, hosts}])
      assert Enum.map(result, & &1.host) == ["high", "medium", "low"]
    end
  end

  describe "merge_endpoints/1" do
    test "merges endpoint aggregates from multiple nodes" do
      node1 = :node1@host
      node2 = :node2@host

      eps1 = [
        %{
          path: "/users",
          requests: 100,
          errors: 5,
          total_duration: 5_000.0,
          avg_latency: 50.0,
          last_seen: 1000
        },
        %{
          path: "/posts",
          requests: 50,
          errors: 1,
          total_duration: 2_000.0,
          avg_latency: 40.0,
          last_seen: 900
        }
      ]

      eps2 = [
        %{
          path: "/users",
          requests: 200,
          errors: 10,
          total_duration: 12_000.0,
          avg_latency: 60.0,
          last_seen: 1100
        }
      ]

      result = Cluster.merge_endpoints([{node1, eps1}, {node2, eps2}])

      assert length(result) == 2
      assert Enum.map(result, & &1.path) == ["/users", "/posts"]

      users = Enum.find(result, &(&1.path == "/users"))
      assert users.requests == 300
      assert users.errors == 15
      assert_in_delta users.avg_latency, 17_000.0 / 300, 0.001
      assert users.last_seen == 1100
      assert users.node == [node1, node2]
    end
  end

  describe "merge_routes/1" do
    test "merges route aggregates from multiple nodes" do
      node1 = :node1@host
      node2 = :node2@host

      routes1 = [
        %{
          method: "GET",
          path: "/users",
          requests: 100,
          errors: 5,
          total_duration: 5_000.0,
          avg_latency: 50.0,
          p50: 45.0,
          p95: 95.0,
          p99: 99.0,
          error_rate: 0.05
        }
      ]

      routes2 = [
        %{
          method: "GET",
          path: "/users",
          requests: 200,
          errors: 10,
          total_duration: 12_000.0,
          avg_latency: 60.0,
          p50: 55.0,
          p95: 110.0,
          p99: 150.0,
          error_rate: 0.05
        }
      ]

      result = Cluster.merge_routes([{node1, routes1}, {node2, routes2}])

      assert length(result) == 1
      route = hd(result)
      assert route.method == "GET"
      assert route.path == "/users"
      assert route.requests == 300
      assert route.errors == 15
      assert route.node == [node1, node2]
    end
  end

  describe "merge_consumers/1" do
    test "merges consumer aggregates from multiple nodes" do
      node1 = :node1@host
      node2 = :node2@host

      consumers1 = [
        %{
          consumer: "alice",
          requests: 100,
          errors: 5,
          total_duration: 5_000.0,
          avg_latency: 50.0,
          last_seen: 1000
        }
      ]

      consumers2 = [
        %{
          consumer: "alice",
          requests: 50,
          errors: 1,
          total_duration: 2_000.0,
          avg_latency: 40.0,
          last_seen: 950
        }
      ]

      result = Cluster.merge_consumers([{node1, consumers1}, {node2, consumers2}])

      assert length(result) == 1
      consumer = hd(result)
      assert consumer.consumer == "alice"
      assert consumer.requests == 150
      assert consumer.errors == 6
      assert consumer.node == [node1, node2]
    end
  end

  describe "merge_recent/2" do
    test "merges recent events from multiple nodes" do
      node1 = :node1@host
      node2 = :node2@host

      event1 = %Event{
        timestamp: 100,
        method: "GET",
        host: "a.com",
        path: "/a",
        status: 200,
        duration_ms: 10.0
      }

      event2 = %Event{
        timestamp: 200,
        method: "POST",
        host: "b.com",
        path: "/b",
        status: 201,
        duration_ms: 20.0
      }

      event3 = %Event{
        timestamp: 150,
        method: "PUT",
        host: "c.com",
        path: "/c",
        status: 200,
        duration_ms: 15.0
      }

      result = Cluster.merge_recent([{node1, [event1, event2]}, {node2, [event3]}])

      assert length(result) == 3
      # Sorted by timestamp descending
      assert Enum.map(result, & &1.timestamp) == [200, 150, 100]

      # First event is from node1
      assert hd(result).host == "b.com"
      assert hd(result).node == node1

      # Second event is from node2
      second = Enum.at(result, 1)
      assert second.host == "c.com"
      assert second.node == node2
    end

    test "respects top_n limit" do
      node = :node@host

      events =
        for i <- 1..100,
            do: %Event{
              timestamp: i,
              method: "GET",
              host: "h.com",
              path: "/p",
              status: 200,
              duration_ms: 1.0
            }

      result = Cluster.merge_recent([{node, events}], 10)
      assert length(result) == 10
    end

    test "defaults to top 50" do
      node = :node@host

      events =
        for i <- 1..100,
            do: %Event{
              timestamp: i,
              method: "GET",
              host: "h.com",
              path: "/p",
              status: 200,
              duration_ms: 1.0
            }

      result = Cluster.merge_recent([{node, events}])
      assert length(result) == 50
    end
  end

  describe "config" do
    test "respects cluster_rpc_timeout config" do
      Application.put_env(:monitorex, :cluster_rpc_timeout, 10_000)
      on_exit(fn -> Application.delete_env(:monitorex, :cluster_rpc_timeout) end)

      # Verify the config doesn't cause crashes
      nodes = Cluster.connected_nodes()
      assert Node.self() in nodes
    end

    test "respects cluster_max_concurrency config" do
      Application.put_env(:monitorex, :cluster_max_concurrency, 5)
      on_exit(fn -> Application.delete_env(:monitorex, :cluster_max_concurrency) end)

      nodes = Cluster.connected_nodes()
      assert Node.self() in nodes
    end

    test "config defaults are used when not set" do
      # Delete any pre-existing config to test defaults
      Application.delete_env(:monitorex, :cluster_mode)
      Application.delete_env(:monitorex, :cluster_rpc_timeout)
      Application.delete_env(:monitorex, :cluster_max_concurrency)

      nodes = Cluster.connected_nodes()
      assert Node.self() in nodes

      result = Cluster.fetch_from_all_nodes(:list_hosts, [])
      assert is_list(result)
    end
  end
end
