defmodule Monitorex.Storage do
  @moduledoc """
  Pure read/query layer over the Collector's ETS tables.

  All functions read directly from named ETS tables — no GenServer calls,
  no casts, no side effects. Designed for read-only access to telemetry data
  collected by `Monitorex.Collector`.
  """

  alias Monitorex.Event

  # ── Defaults ──

  @default_limit 50

  # ── Outbound Queries ──

  @doc """
  Returns list of host aggregates from `:monitorex_outbound_hosts`,
  sorted by requests descending.

  Each entry includes computed p50, p95, p99 from duration samples
  and the error rate.
  """
  @spec list_hosts() :: [map()]
  def list_hosts do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc -> [build_host_entry(host, agg) | acc] end,
        [],
        :monitorex_outbound_hosts
      )
      |> Enum.sort_by(& &1.requests, :desc)
    end)
  end

  @doc """
  Returns list of endpoint aggregates for a given host.

  Queries `:monitorex_outbound_endpoints` for entries whose key matches
  the given host (key is `{host, path}`).
  """
  @spec list_endpoints_for_host(String.t()) :: [map()]
  def list_endpoints_for_host(host) do
    with_table(:monitorex_outbound_endpoints, fn ->
      :ets.foldl(
        fn
          {{h, path}, agg}, acc when h == host ->
            [build_endpoint_entry(path, agg) | acc]

          _, acc ->
            acc
        end,
        [],
        :monitorex_outbound_endpoints
      )
    end)
  end

  @doc """
  Returns most recent outbound Events with optional filtering.

  ## Options

    * `:limit` — maximum number of events to return (default: 50, must be positive)
    * `:offset` — number of events to skip (default: 0)
    * `:status_class` — filter by status class atom (e.g. `:error`, `:success`).
      `nil` or omission means no filter.
    * `:host` — filter by exact host match. `nil` or omission means no filter.
  """
  @spec list_recent_outbound(keyword()) :: [Event.t()]
  def list_recent_outbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    status_class = Keyword.get(opts, :status_class)
    host = Keyword.get(opts, :host)

    with_table(:monitorex_outbound_recent, fn ->
      :monitorex_outbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} -> passes_outbound_filter?(event, status_class, host) end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {_ts, event} -> event end)
    end)
  end

  # ── Inbound Queries ──

  @doc """
  Returns route aggregates from `:monitorex_inbound_routes`, sorted by requests
  descending.

  Parses the "Method:path" key into separate `:method` and `:path` fields.
  Each entry includes computed p50, p95, p99 from duration samples and error rate.
  """
  @spec list_routes() :: [map()]
  def list_routes do
    with_table(:monitorex_inbound_routes, fn ->
      :ets.foldl(
        fn {route_key, agg}, acc -> [build_route_entry(route_key, agg) | acc] end,
        [],
        :monitorex_inbound_routes
      )
      |> Enum.sort_by(& &1.requests, :desc)
    end)
  end

  @doc """
  Returns consumer aggregates from `:monitorex_inbound_consumers`,
  sorted by requests descending.
  """
  @spec list_consumers() :: [map()]
  def list_consumers do
    with_table(:monitorex_inbound_consumers, fn ->
      :ets.foldl(
        fn {consumer, agg}, acc ->
          [
            %{
              consumer: consumer,
              requests: agg.requests || 0,
              errors: agg.errors || 0,
              total_duration: agg.total_duration || 0.0,
              last_seen: agg.last_seen
            }
            | acc
          ]
        end,
        [],
        :monitorex_inbound_consumers
      )
      |> Enum.sort_by(& &1.requests, :desc)
    end)
  end

  @doc """
  Returns most recent inbound Events with optional filtering.

  ## Options

    * `:limit` — maximum number of events to return (default: 50, must be positive)
    * `:offset` — number of events to skip (default: 0)
    * `:status_class` — filter by status class atom (e.g. `:error`, `:success`).
      `nil` or omission means no filter.
    * `:consumer` — filter by exact consumer match.
    * `:route` — filter by route key (`"Method:path"`).
  """
  @spec list_recent_inbound(keyword()) :: [Event.t()]
  def list_recent_inbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    status_class = Keyword.get(opts, :status_class)
    consumer = Keyword.get(opts, :consumer)
    route = Keyword.get(opts, :route)

    with_table(:monitorex_inbound_recent, fn ->
      :monitorex_inbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} ->
        passes_inbound_filter?(event, status_class, consumer, route)
      end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {_ts, event} -> event end)
    end)
  end

  @doc """
  Returns consumer breakdown for a given route key (`"Method:path"`).

  Queries `:monitorex_inbound_recent`, groups events by consumer, and
  computes aggregate stats (requests, errors, total_duration, avg_latency,
  last_seen) for each consumer on that route.
  """
  @spec list_consumers_for_route(String.t()) :: [map()]
  def list_consumers_for_route(route_key) do
    with_table(:monitorex_inbound_recent, fn ->
      route = parse_route_key(route_key)

      :monitorex_inbound_recent
      |> :ets.tab2list()
      |> Enum.reduce(%{}, fn
        {_ts, %Event{method: method, path: path, consumer: consumer} = event}, acc
        when not is_nil(consumer) and method == route.method and path == route.path ->
          Map.update(acc, consumer, new_consumer_agg(event), fn existing ->
            increment_consumer_agg(existing, event)
          end)

        _, acc ->
          acc
      end)
      |> Enum.map(fn {consumer, agg} -> finalize_consumer_agg(consumer, agg) end)
      |> Enum.sort_by(& &1.requests, :desc)
    end)
  end

  # ── Private helpers ──

  # Guards against missing ETS tables — returns [] if the table doesn't exist.
  defp with_table(table_name, fun) do
    case :ets.info(table_name) do
      :undefined -> []
      _ -> fun.()
    end
  end

  # ── Host entry ──

  defp build_host_entry(host, agg) do
    requests = agg.requests || 0
    errors = agg.errors || 0
    total_duration = agg.total_duration || 0.0
    avg_latency = if requests > 0, do: total_duration / requests, else: 0.0
    error_rate = if requests > 0, do: errors / requests, else: 0.0

    {p50, p95, p99} = compute_host_percentiles(host)

    %{
      host: host,
      client: agg[:client],
      requests: requests,
      errors: errors,
      error_rate: error_rate,
      total_duration: total_duration,
      avg_latency: avg_latency,
      p50: p50,
      p95: p95,
      p99: p99
    }
  end

  defp compute_host_percentiles(host) do
    case :ets.info(:monitorex_outbound_duration_samples) do
      :undefined ->
        {nil, nil, nil}

      _ ->
        samples =
          :ets.lookup(:monitorex_outbound_duration_samples, host)
          |> Enum.map(fn {^host, ms} -> ms end)
          |> Enum.sort()

        case samples do
          [] -> {nil, nil, nil}
          _ -> {compute_percentile(samples, 50), compute_percentile(samples, 95), compute_percentile(samples, 99)}
        end
    end
  end

  # ── Endpoint entry ──

  defp build_endpoint_entry(path, agg) do
    requests = agg.requests || 0
    errors = agg.errors || 0
    total_duration = agg.total_duration || 0.0
    avg_latency = if requests > 0, do: total_duration / requests, else: 0.0

    %{
      path: path,
      requests: requests,
      errors: errors,
      total_duration: total_duration,
      avg_latency: avg_latency,
      last_seen: agg.last_seen
    }
  end

  # ── Route entry ──

  defp build_route_entry(route_key, agg) do
    [method, path] = String.split(route_key, ":", parts: 2)
    requests = agg.requests || 0
    errors = agg.errors || 0
    total_duration = agg.total_duration || 0.0
    avg_latency = if requests > 0, do: total_duration / requests, else: 0.0
    error_rate = if requests > 0, do: errors / requests, else: 0.0

    {p50, p95, p99} = compute_route_percentiles(route_key)

    %{
      method: method,
      path: path,
      requests: requests,
      errors: errors,
      error_rate: error_rate,
      total_duration: total_duration,
      avg_latency: avg_latency,
      p50: p50,
      p95: p95,
      p99: p99
    }
  end

  defp compute_route_percentiles(route_key) do
    case :ets.info(:monitorex_inbound_duration_samples) do
      :undefined ->
        {nil, nil, nil}

      _ ->
        samples =
          :ets.lookup(:monitorex_inbound_duration_samples, route_key)
          |> Enum.map(fn {^route_key, ms} -> ms end)
          |> Enum.sort()

        case samples do
          [] -> {nil, nil, nil}
          _ -> {compute_percentile(samples, 50), compute_percentile(samples, 95), compute_percentile(samples, 99)}
        end
    end
  end

  # ── Percentile computation ──

  defp compute_percentile(samples, p) do
    len = length(samples)
    rank = max(1, round(len * p / 100))
    Enum.at(samples, rank - 1)
  end

  @doc """
  Returns count of recent outbound events matching optional filters.

  Same filtering as `list_recent_outbound/1` but returns count instead of events.
  """
  @spec count_recent_outbound(keyword()) :: non_neg_integer()
  def count_recent_outbound(opts \\ []) do
    status_class = Keyword.get(opts, :status_class)
    host = Keyword.get(opts, :host)

    with_table(:monitorex_outbound_recent, fn ->
      :monitorex_outbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} -> passes_outbound_filter?(event, status_class, host) end)
      |> length()
    end)
  end

  @doc """
  Returns count of recent inbound events matching optional filters.

  Same filtering as `list_recent_inbound/1` but returns count instead of events.
  """
  @spec count_recent_inbound(keyword()) :: non_neg_integer()
  def count_recent_inbound(opts \\ []) do
    status_class = Keyword.get(opts, :status_class)
    consumer = Keyword.get(opts, :consumer)
    route = Keyword.get(opts, :route)

    with_table(:monitorex_inbound_recent, fn ->
      :monitorex_inbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} ->
        passes_inbound_filter?(event, status_class, consumer, route)
      end)
      |> length()
    end)
  end

  # ── Filtering helpers ──

  defp passes_outbound_filter?(event, status_class, host) do
    (is_nil(status_class) || event.status_class == status_class) &&
      (is_nil(host) || event.host == host)
  end

  defp passes_inbound_filter?(event, status_class, consumer, route) do
    (is_nil(status_class) || event.status_class == status_class) &&
      (is_nil(consumer) || event.consumer == consumer) &&
      (is_nil(route) || route_matches?(event, route))
  end

  defp route_matches?(event, route_key) do
    "#{event.method}:#{event.path}" == route_key
  end

  defp parse_route_key(route_key) do
    [method, path] = String.split(route_key, ":", parts: 2)
    %{method: method, path: path}
  end

  # ── Consumer aggregation helpers ──

  defp new_consumer_agg(event) do
    %{
      requests: 1,
      errors: if(error_event?(event), do: 1, else: 0),
      total_duration: event.duration_ms || 0.0,
      last_seen: event.timestamp || 0
    }
  end

  defp increment_consumer_agg(agg, event) do
    %{
      agg
      | requests: agg.requests + 1,
        errors: agg.errors + if(error_event?(event), do: 1, else: 0),
        total_duration: agg.total_duration + (event.duration_ms || 0.0),
        last_seen: max(agg.last_seen, event.timestamp || 0)
    }
  end

  defp finalize_consumer_agg(consumer, agg) do
    requests = agg.requests
    total_duration = agg.total_duration
    avg_latency = if requests > 0, do: total_duration / requests, else: 0.0

    %{
      consumer: consumer,
      requests: requests,
      errors: agg.errors,
      total_duration: total_duration,
      avg_latency: avg_latency,
      last_seen: agg.last_seen
    }
  end

  defp error_event?(%Event{status_class: status_class}) do
    status_class in [:client_error, :server_error]
  end
end
