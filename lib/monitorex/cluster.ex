defmodule Monitorex.Cluster do
  @moduledoc """
  Cluster support for Monitorex — provides multi-node data aggregation
  across distributed Erlang nodes.

  Use `fetch_from_all_nodes/2` to query all nodes in the cluster, then
  pass the results to the appropriate `merge_*` function to produce
  consolidated aggregates.
  """

  alias Monitorex.Storage

  # ── Config defaults ──

  @default_cluster_mode :auto
  @default_cluster_rpc_timeout 5_000
  @default_cluster_max_concurrency 3

  # ── Configuration ──

  defp cluster_mode, do: Application.get_env(:monitorex, :cluster_mode, @default_cluster_mode)

  defp rpc_timeout,
    do: Application.get_env(:monitorex, :cluster_rpc_timeout, @default_cluster_rpc_timeout)

  defp max_concurrency,
    do:
      Application.get_env(:monitorex, :cluster_max_concurrency, @default_cluster_max_concurrency)

  # ── connected_nodes/0 ──

  @doc """
  Returns all reachable nodes including `Node.self()`.

  When `cluster_mode` config is `:single`, returns only `[Node.self()]`.
  Otherwise returns `[Node.self() | Node.list()]`.
  """
  @spec connected_nodes() :: [node()]
  def connected_nodes do
    case cluster_mode() do
      :single -> [Node.self()]
      _ -> [Node.self() | Node.list()]
    end
  end

  # ── fetch_from_all_nodes/2 ──

  @doc """
  Calls the given `Storage` function on **all** connected nodes via RPC.

  Returns a list of `{node, result}` tuples for successful calls.
  Nodes that return `{:badrpc, _}` are silently omitted.

  ## Parameters

    * `func_name` — atom name of a function on `Monitorex.Storage`
      (e.g. `:list_hosts`, `:list_routes`, `:list_recent_outbound`)
    * `args` — list of arguments to pass to the function

  ## Configuration

    * `:cluster_max_concurrency` — max concurrent RPC calls (default `3`)
    * `:cluster_rpc_timeout` — per-call timeout in ms (default `5_000`)
  """
  @spec fetch_from_all_nodes(atom(), list()) :: [{node(), term()}]
  def fetch_from_all_nodes(func_name, args) do
    nodes = connected_nodes()

    nodes
    |> Task.async_stream(
      fn node ->
        case :rpc.call(node, Storage, func_name, args, rpc_timeout()) do
          {:badrpc, _reason} -> {:skip, node}
          result -> {node, result}
        end
      end,
      max_concurrency: max_concurrency(),
      timeout: rpc_timeout() + 1_000
    )
    |> Enum.reduce([], fn
      {:ok, {:skip, _node}}, acc -> acc
      {:ok, {node, result}}, acc -> [{node, result} | acc]
      {:exit, _reason}, acc -> acc
    end)
    |> Enum.reverse()
  end

  # ── Merge: Hosts ──

  @doc """
  Merges host aggregates collected from multiple nodes.

  ## Input

  A list of `{node, [host_map]}` tuples — as returned by
  `fetch_from_all_nodes(:list_hosts, [])`.

  ## Merge strategy

    * `requests`, `errors`, `total_duration` are summed
    * `avg_latency` is recomputed as `total_duration / requests`
    * `p50`, `p95`, `p99` are weighted by each node's request count
    * `:node` is set to a list of all source nodes that contributed
  """
  @spec merge_hosts([{node(), [map()]}]) :: [map()]
  def merge_hosts(node_hosts) do
    merge_aggregates(node_hosts, &host_key/1, &finalize_host/1)
  end

  # ── Merge: Endpoints ──

  @doc """
  Merges endpoint aggregates from multiple nodes.

  Same merge strategy as `merge_hosts/1` but for endpoint data.
  """
  @spec merge_endpoints([{node(), [map()]}]) :: [map()]
  def merge_endpoints(node_endpoints) do
    merge_aggregates(node_endpoints, &endpoint_key/1, &finalize_endpoint/1)
  end

  # ── Merge: Routes ──

  @doc """
  Merges route aggregates from multiple nodes.

  Same merge strategy as `merge_hosts/1` but for route data.
  """
  @spec merge_routes([{node(), [map()]}]) :: [map()]
  def merge_routes(node_routes) do
    merge_aggregates(node_routes, &route_key/1, &finalize_route/1)
  end

  # ── Merge: Consumers ──

  @doc """
  Merges consumer aggregates from multiple nodes.

  Same merge strategy as `merge_hosts/1` but for consumer data.
  """
  @spec merge_consumers([{node(), [map()]}]) :: [map()]
  def merge_consumers(node_consumers) do
    merge_aggregates(node_consumers, &consumer_key/1, &finalize_consumer/1)
  end

  # ── Merge: Recent events ──

  @doc """
  Merges recent event lists from multiple nodes.

  ## Input

  A list of `{node, [event_struct]}` tuples.

  ## Merge strategy

    * All events are flattened into a single list
    * Each event is tagged with its source `:node`
    * Sorted by `timestamp` descending
    * Returns the top `top_n` events (default `50`)
  """
  @spec merge_recent([{node(), [map()]}], pos_integer()) :: [map()]
  def merge_recent(node_events, top_n \\ 50) do
    node_events
    |> Enum.flat_map(fn {node, events} ->
      Enum.map(events, &Map.put(&1, :node, node))
    end)
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(top_n)
  end

  # ── Internal helpers ──

  defp merge_aggregates(node_lists, key_fn, finalize_fn) do
    node_lists
    |> Enum.flat_map(fn {node, items} ->
      Enum.map(items, &Map.put(&1, :node, node))
    end)
    |> Enum.group_by(key_fn)
    |> Enum.map(fn {_key, items} -> finalize_fn.(items) end)
    |> Enum.sort_by(& &1.requests, :desc)
  end

  defp host_key(item), do: item.host
  defp endpoint_key(item), do: item.path
  defp route_key(item), do: {item.method, item.path}
  defp consumer_key(item), do: item.consumer

  defp finalize_host(items) do
    first = hd(items)
    total_requests = Enum.reduce(items, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(items, 0, &(&1.errors + &2))
    total_duration = Enum.reduce(items, 0, &(&1.total_duration + &2))
    avg_latency = if total_requests > 0, do: total_duration / total_requests, else: 0.0

    %{
      host: first.host,
      requests: total_requests,
      errors: total_errors,
      error_rate: if(total_requests > 0, do: total_errors / total_requests, else: 0.0),
      total_duration: total_duration,
      avg_latency: avg_latency,
      p50: weighted_percentile(items, :p50),
      p95: weighted_percentile(items, :p95),
      p99: weighted_percentile(items, :p99),
      node: Enum.map(items, & &1.node)
    }
  end

  defp finalize_endpoint(items) do
    first = hd(items)
    total_requests = Enum.reduce(items, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(items, 0, &(&1.errors + &2))
    total_duration = Enum.reduce(items, 0, &(&1.total_duration + &2))
    avg_latency = if total_requests > 0, do: total_duration / total_requests, else: 0.0

    %{
      path: first.path,
      requests: total_requests,
      errors: total_errors,
      total_duration: total_duration,
      avg_latency: avg_latency,
      last_seen: Enum.max_by(items, &(&1.last_seen || 0)).last_seen,
      node: Enum.map(items, & &1.node)
    }
  end

  defp finalize_route(items) do
    first = hd(items)
    total_requests = Enum.reduce(items, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(items, 0, &(&1.errors + &2))
    total_duration = Enum.reduce(items, 0, &(&1.total_duration + &2))
    avg_latency = if total_requests > 0, do: total_duration / total_requests, else: 0.0

    %{
      method: first.method,
      path: first.path,
      requests: total_requests,
      errors: total_errors,
      error_rate: if(total_requests > 0, do: total_errors / total_requests, else: 0.0),
      total_duration: total_duration,
      avg_latency: avg_latency,
      p50: weighted_percentile(items, :p50),
      p95: weighted_percentile(items, :p95),
      p99: weighted_percentile(items, :p99),
      node: Enum.map(items, & &1.node)
    }
  end

  defp finalize_consumer(items) do
    first = hd(items)
    total_requests = Enum.reduce(items, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(items, 0, &(&1.errors + &2))
    total_duration = Enum.reduce(items, 0, &(&1.total_duration + &2))
    avg_latency = if total_requests > 0, do: total_duration / total_requests, else: 0.0

    %{
      consumer: first.consumer,
      requests: total_requests,
      errors: total_errors,
      total_duration: total_duration,
      avg_latency: avg_latency,
      last_seen: Enum.max_by(items, &(&1.last_seen || 0)).last_seen,
      node: Enum.map(items, & &1.node)
    }
  end

  defp weighted_percentile(items, field) do
    total_requests = Enum.reduce(items, 0, &(&1.requests + &2))

    if total_requests == 0 do
      nil
    else
      items
      |> Enum.reduce(0, fn item, acc ->
        acc + (item[field] || 0) * (item.requests / total_requests)
      end)
    end
  end
end
