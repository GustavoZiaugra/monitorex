defmodule Monitorex.ClusterPage do
  @moduledoc """
  Helper that delegates to `Monitorex.Cluster` (multi-node) or `Monitorex.Storage`
  (local) based on the `:cluster_mode` config.

  Used by LiveView pages to transparently aggregate data across BEAM nodes
  when running in cluster mode, while falling back to local reads when in
  `:single` mode (the default).

  ## Config

  Set `Application.get_env(:monitorex, :cluster_mode)` to one of:

    * `:single` — read from local ETS tables only (default)
    * `:auto` — use Cluster if more than one node is visible
    * `:cluster` — always use Cluster (multi-node RPC)

  See `Monitorex.Cluster` for detailed merge strategies and configuration options.
  """

  alias Monitorex.Cluster
  alias Monitorex.Storage

  # ── Mode detection ──

  @doc false
  def cluster_mode do
    Application.get_env(:monitorex, :cluster_mode, :single)
  end

  @doc false
  def cluster_enabled? do
    case cluster_mode() do
      :single -> false
      :auto -> length(Cluster.connected_nodes()) > 1
      :cluster -> true
    end
  end

  # ── Outbound queries ──

  @doc """
  Returns hosts — either from local Storage or aggregated across all cluster nodes.
  """
  @spec list_hosts() :: [map()]
  def list_hosts do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:list_hosts, [])
      |> Cluster.merge_hosts()
    else
      Storage.list_hosts()
    end
  end

  @doc """
  Returns endpoints for a host — either from local Storage or aggregated across
  all cluster nodes.
  """
  @spec list_endpoints_for_host(String.t()) :: [map()]
  def list_endpoints_for_host(host) do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:list_endpoints_for_host, [host])
      |> Cluster.merge_endpoints()
    else
      Storage.list_endpoints_for_host(host)
    end
  end

  @doc """
  Returns recent outbound events — either from local Storage or merged across
  all cluster nodes.
  """
  @spec list_recent_outbound(keyword()) :: [map()]
  def list_recent_outbound(opts \\ []) do
    if cluster_enabled?() do
      limit = Keyword.get(opts, :limit, 50)

      Cluster.fetch_from_all_nodes(:list_recent_outbound, [opts])
      |> Cluster.merge_recent(limit)
    else
      Storage.list_recent_outbound(opts)
    end
  end

  @doc """
  Returns count of recent outbound events — either from local Storage or
  summed across all cluster nodes.
  """
  @spec count_recent_outbound(keyword()) :: non_neg_integer()
  def count_recent_outbound(opts \\ []) do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:count_recent_outbound, [opts])
      |> Enum.reduce(0, fn {_node, count}, acc -> acc + count end)
    else
      Storage.count_recent_outbound(opts)
    end
  end

  # ── Inbound queries ──

  @doc """
  Returns routes — either from local Storage or aggregated across all
  cluster nodes.
  """
  @spec list_routes() :: [map()]
  def list_routes do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:list_routes, [])
      |> Cluster.merge_routes()
    else
      Storage.list_routes()
    end
  end

  @doc """
  Returns consumers — either from local Storage or aggregated across all
  cluster nodes.
  """
  @spec list_consumers() :: [map()]
  def list_consumers do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:list_consumers, [])
      |> Cluster.merge_consumers()
    else
      Storage.list_consumers()
    end
  end

  @doc """
  Returns consumers for a route — either from local Storage or aggregated
  across all cluster nodes.
  """
  @spec list_consumers_for_route(String.t()) :: [map()]
  def list_consumers_for_route(route) do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:list_consumers_for_route, [route])
      |> Cluster.merge_consumers()
    else
      Storage.list_consumers_for_route(route)
    end
  end

  @doc """
  Returns recent inbound events — either from local Storage or merged across
  all cluster nodes.
  """
  @spec list_recent_inbound(keyword()) :: [map()]
  def list_recent_inbound(opts \\ []) do
    if cluster_enabled?() do
      limit = Keyword.get(opts, :limit, 50)

      Cluster.fetch_from_all_nodes(:list_recent_inbound, [opts])
      |> Cluster.merge_recent(limit)
    else
      Storage.list_recent_inbound(opts)
    end
  end

  @doc """
  Returns count of recent inbound events — either from local Storage or
  summed across all cluster nodes.
  """
  @spec count_recent_inbound(keyword()) :: non_neg_integer()
  def count_recent_inbound(opts \\ []) do
    if cluster_enabled?() do
      Cluster.fetch_from_all_nodes(:count_recent_inbound, [opts])
      |> Enum.reduce(0, fn {_node, count}, acc -> acc + count end)
    else
      Storage.count_recent_inbound(opts)
    end
  end
end
