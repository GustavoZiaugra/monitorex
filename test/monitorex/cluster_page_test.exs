defmodule Monitorex.ClusterPageTest do
  use ExUnit.Case, async: false
  alias Monitorex.ClusterPage

  setup do
    Application.put_env(:monitorex, :cluster_mode, :single)
    on_exit(fn -> Application.delete_env(:monitorex, :cluster_mode) end)
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
  end

  describe "list_routes/0" do
    test "returns local routes when cluster_mode is :single" do
      result = ClusterPage.list_routes()
      assert is_list(result)
      assert result == []
    end
  end

  describe "list_consumers/0" do
    test "returns local consumers when cluster_mode is :single" do
      result = ClusterPage.list_consumers()
      assert is_list(result)
      assert result == []
    end
  end

  describe "list_endpoints_for_host/1" do
    test "returns local endpoints when cluster_mode is :single" do
      result = ClusterPage.list_endpoints_for_host("example.com")
      assert is_list(result)
      assert result == []
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
  end

  describe "count_recent_outbound/1" do
    test "returns empty when no data" do
      assert ClusterPage.count_recent_outbound() == []
    end
    test "passes keyword options through" do
      assert ClusterPage.count_recent_outbound(host: "example.com") == []
    end
  end

  describe "count_recent_inbound/1" do
    test "returns empty when no data" do
      assert ClusterPage.count_recent_inbound() == []
    end
    test "passes keyword options through" do
      assert ClusterPage.count_recent_inbound(consumer: "test") == []
    end
  end

  describe "list_consumers_for_route/1" do
    test "returns local consumers for route when cluster_mode is :single" do
      result = ClusterPage.list_consumers_for_route("GET:/api/test")
      assert is_list(result)
      assert result == []
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
end
