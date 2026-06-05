defmodule Monitorex.Storage.ETS do
  @moduledoc """
  ETS-backed implementation of `Monitorex.Storage.Backend`.

  This is the default storage backend. It reads from and writes to the
  named ETS tables created by `Monitorex.Collector`.
  """

  @behaviour Monitorex.Storage.Backend

  alias Monitorex.Event

  # ── Table names ──

  @outbound_hosts :monitorex_outbound_hosts
  @outbound_endpoints :monitorex_outbound_endpoints
  @outbound_recent :monitorex_outbound_recent
  @outbound_duration_samples :monitorex_outbound_duration_samples

  @inbound_routes :monitorex_inbound_routes
  @inbound_consumers :monitorex_inbound_consumers
  @inbound_recent :monitorex_inbound_recent
  @inbound_duration_samples :monitorex_inbound_duration_samples

  @outbound_slow :monitorex_slow_outbound
  @inbound_slow :monitorex_slow_inbound

  @default_limit 50

  # ── Write callbacks ──

  @impl true
  def record_event(%Event{} = event) do
    event = truncate_bodies(event)

    case event.direction do
      :outbound -> write_outbound(event)
      :inbound -> write_inbound(event)
    end

    :ok
  end

  @impl true
  def prune do
    max_recent = Application.get_env(:monitorex, :max_recent, 500)
    max_recent_inbound = Application.get_env(:monitorex, :max_recent_inbound, 500)
    max_slow = Application.get_env(:monitorex, :max_slow, 200)
    max_endpoints = Application.get_env(:monitorex, :max_endpoints, 2_000)
    endpoint_ttl = Application.get_env(:monitorex, :endpoint_ttl, :timer.hours(1))
    wall_now = System.system_time(:microsecond)

    trim_recent(@outbound_recent, max_recent)
    trim_recent(@inbound_recent, max_recent_inbound)
    trim_recent(@outbound_slow, max_slow)
    trim_recent(@inbound_slow, max_slow)

    prune_stale(@outbound_hosts, wall_now, endpoint_ttl)
    prune_stale(@outbound_endpoints, wall_now, endpoint_ttl)
    prune_stale(@inbound_routes, wall_now, endpoint_ttl)
    prune_stale(@inbound_consumers, wall_now, endpoint_ttl)

    trim_aggregate(@outbound_hosts, max_endpoints)
    trim_aggregate(@outbound_endpoints, max_endpoints)
    trim_aggregate(@inbound_routes, max_endpoints)
    trim_aggregate(@inbound_consumers, max_endpoints)

    compute_percentiles(:outbound)
    compute_percentiles(:inbound)

    :ok
  end

  # ── Read callbacks ──

  @impl true
  def list_hosts do
    with_table(@outbound_hosts, fn ->
      Enum.sort_by(
        :ets.foldl(
          fn {host, agg}, acc -> [build_host_entry(host, agg) | acc] end,
          [],
          @outbound_hosts
        ),
        & &1.requests,
        :desc
      )
    end)
  end

  @impl true
  def list_endpoints_for_host(host) do
    with_table(@outbound_endpoints, fn ->
      :ets.foldl(
        fn
          {{^host, path}, agg}, acc -> [build_endpoint_entry(path, agg) | acc]
          _, acc -> acc
        end,
        [],
        @outbound_endpoints
      )
    end)
  end

  @impl true
  def list_recent_outbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    status_class = Keyword.get(opts, :status_class)
    host = Keyword.get(opts, :host)

    with_table(@outbound_recent, fn ->
      @outbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} ->
        passes_outbound_filter?(event, status_class, host)
      end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {_ts, event} -> event end)
    end)
  end

  @impl true
  def list_routes do
    with_table(@inbound_routes, fn ->
      Enum.sort_by(
        :ets.foldl(
          fn {route_key, agg}, acc -> [build_route_entry(route_key, agg) | acc] end,
          [],
          @inbound_routes
        ),
        & &1.requests,
        :desc
      )
    end)
  end

  @impl true
  def list_consumers do
    with_table(@inbound_consumers, fn ->
      Enum.sort_by(
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
          @inbound_consumers
        ),
        & &1.requests,
        :desc
      )
    end)
  end

  @impl true
  def list_recent_inbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    status_class = Keyword.get(opts, :status_class)
    consumer = Keyword.get(opts, :consumer)
    route = Keyword.get(opts, :route)

    with_table(@inbound_recent, fn ->
      @inbound_recent
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

  @impl true
  def list_consumers_for_route(route_key) do
    with_table(@inbound_recent, fn ->
      route = parse_route_key(route_key)

      @inbound_recent
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

  @impl true
  def get_event(timestamp) when is_integer(timestamp) do
    outbound_exists = :ets.info(@outbound_recent) != :undefined
    inbound_exists = :ets.info(@inbound_recent) != :undefined

    cond do
      outbound_exists ->
        case :ets.lookup(@outbound_recent, timestamp) do
          [{^timestamp, event}] -> event
          [] -> if inbound_exists, do: lookup_inbound(timestamp), else: nil
        end

      inbound_exists ->
        lookup_inbound(timestamp)

      true ->
        nil
    end
  end

  @impl true
  def count_recent_outbound(opts \\ []) do
    status_class = Keyword.get(opts, :status_class)
    host = Keyword.get(opts, :host)

    with_table(@outbound_recent, fn ->
      @outbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} -> passes_outbound_filter?(event, status_class, host) end)
      |> length()
    end)
  end

  @impl true
  def count_recent_inbound(opts \\ []) do
    status_class = Keyword.get(opts, :status_class)
    consumer = Keyword.get(opts, :consumer)
    route = Keyword.get(opts, :route)

    with_table(@inbound_recent, fn ->
      @inbound_recent
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.filter(fn {_ts, event} ->
        passes_inbound_filter?(event, status_class, consumer, route)
      end)
      |> length()
    end)
  end

  @impl true
  def list_slow_outbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    with_table(@outbound_slow, fn ->
      @outbound_slow
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.take(limit)
      |> Enum.map(fn {_ts, event} -> event end)
    end)
  end

  @impl true
  def list_slow_inbound(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    with_table(@inbound_slow, fn ->
      @inbound_slow
      |> :ets.tab2list()
      |> Enum.reverse()
      |> Enum.take(limit)
      |> Enum.map(fn {_ts, event} -> event end)
    end)
  end

  # ── Private: write helpers ──

  defp write_outbound(event) do
    host = event.host || "unknown"
    ts = System.system_time(:microsecond)

    update_aggregate(@outbound_hosts, host, event)
    update_aggregate(@outbound_endpoints, {host, event.path}, event)

    :ets.insert(@outbound_recent, {ts, event})

    if event.duration_ms do
      :ets.insert(@outbound_duration_samples, {host, event.duration_ms})
    end

    if event.slow do
      :ets.insert(@outbound_slow, {ts, event})
    end
  end

  defp write_inbound(event) do
    route_key = "#{event.method}:#{event.path}"
    ts = System.system_time(:microsecond)

    update_aggregate(@inbound_routes, route_key, event)

    if event.consumer do
      update_aggregate(@inbound_consumers, event.consumer, event)
    end

    :ets.insert(@inbound_recent, {ts, event})

    if event.duration_ms do
      :ets.insert(@inbound_duration_samples, {route_key, event.duration_ms})
    end

    if event.slow do
      :ets.insert(@inbound_slow, {ts, event})
    end
  end

  defp update_aggregate(table, key, event) do
    case :ets.lookup(table, key) do
      [{^key, agg}] ->
        :ets.insert(table, {key, increment_aggregate(agg, event)})

      [] ->
        :ets.insert(table, {key, new_aggregate(event)})
    end
  end

  defp new_aggregate(event) do
    %{
      requests: 1,
      errors: if(error_status?(event.status), do: 1, else: 0),
      total_duration: event.duration_ms || 0.0,
      last_seen: System.system_time(:microsecond)
    }
  end

  defp increment_aggregate(agg, event) do
    %{
      agg
      | requests: agg.requests + 1,
        errors: agg.errors + if(error_status?(event.status), do: 1, else: 0),
        total_duration: agg.total_duration + (event.duration_ms || 0.0),
        last_seen: System.system_time(:microsecond)
    }
  end

  defp error_status?(status) when is_integer(status) and status >= 400, do: true
  defp error_status?(_), do: false

  defp truncate_bodies(event) do
    max = Application.get_env(:monitorex, :max_body_bytes, 10_000)

    %{
      event
      | request_body: maybe_truncate(event.request_body, max),
        response_body: maybe_truncate(event.response_body, max)
    }
  end

  defp maybe_truncate(nil, _max), do: nil

  defp maybe_truncate(body, max) when is_binary(body) do
    if byte_size(body) > max do
      binary_part(body, 0, max)
    else
      body
    end
  end

  # ── Private: prune helpers ──

  defp trim_recent(table, max) do
    count = :ets.info(table, :size)

    if is_integer(count) and count > max do
      to_delete = count - max

      first_keys =
        :ets.foldl(
          fn
            {key, _}, acc when length(acc) < to_delete -> [key | acc]
            _, acc -> acc
          end,
          [],
          table
        )

      Enum.each(first_keys, &:ets.delete(table, &1))
    end
  end

  defp trim_aggregate(table, max) do
    count = :ets.info(table, :size)

    if is_integer(count) and count > max do
      to_delete = count - max

      entries =
        :ets.foldl(
          fn {key, agg}, acc -> [{key, Map.get(agg, :last_seen, 0)} | acc] end,
          [],
          table
        )

      entries
      |> Enum.sort_by(fn {_key, ts} -> ts end, :asc)
      |> Enum.take(to_delete)
      |> Enum.each(fn {key, _ts} -> :ets.delete(table, key) end)
    end
  end

  defp prune_stale(table, wall_now, ttl_ms) do
    case :ets.info(table) do
      :undefined ->
        :ok

      _ ->
        to_delete =
          :ets.foldl(
            fn {key, agg}, acc ->
              elapsed_ms = div(wall_now - agg.last_seen, 1000)
              if elapsed_ms > ttl_ms, do: [key | acc], else: acc
            end,
            [],
            table
          )

        Enum.each(to_delete, &:ets.delete(table, &1))
    end
  end

  defp compute_percentiles(:outbound) do
    hosts =
      case :ets.info(@outbound_hosts) do
        :undefined -> []
        _ -> Enum.uniq(:ets.foldl(fn {host, _}, acc -> [host | acc] end, [], @outbound_hosts))
      end

    Enum.each(hosts, fn host ->
      samples =
        @outbound_duration_samples
        |> :ets.lookup(host)
        |> Enum.map(fn {^host, ms} -> ms end)
        |> Enum.sort()

      if length(samples) >= 10 do
        {p50, p95, p99} = compute_percentile_values(samples)

        case :ets.lookup(@outbound_hosts, host) do
          [{^host, agg}] ->
            :ets.insert(@outbound_hosts, {host, Map.merge(agg, %{p50: p50, p95: p95, p99: p99})})

          _ ->
            :ok
        end

        :ets.delete(@outbound_duration_samples, host)
      end
    end)
  end

  defp compute_percentiles(:inbound) do
    routes =
      case :ets.info(@inbound_routes) do
        :undefined -> []
        _ -> Enum.uniq(:ets.foldl(fn {key, _}, acc -> [key | acc] end, [], @inbound_routes))
      end

    Enum.each(routes, fn route_key ->
      samples =
        @inbound_duration_samples
        |> :ets.lookup(route_key)
        |> Enum.map(fn {^route_key, ms} -> ms end)
        |> Enum.sort()

      if length(samples) >= 10 do
        {p50, p95, p99} = compute_percentile_values(samples)

        case :ets.lookup(@inbound_routes, route_key) do
          [{^route_key, agg}] ->
            :ets.insert(
              @inbound_routes,
              {route_key, Map.merge(agg, %{p50: p50, p95: p95, p99: p99})}
            )

          _ ->
            :ok
        end

        :ets.delete(@inbound_duration_samples, route_key)
      end
    end)
  end

  defp compute_percentile_values(sorted_samples) do
    len = length(sorted_samples)
    p50 = percentile(sorted_samples, len, 50)
    p95 = percentile(sorted_samples, len, 95)
    p99 = percentile(sorted_samples, len, 99)
    {p50, p95, p99}
  end

  defp percentile(_samples, 0, _p), do: 0.0

  defp percentile(samples, len, p) when len > 0 do
    rank = max(1, round(len * p / 100))
    Enum.at(samples, rank - 1)
  end

  # ── Private: read helpers ──

  defp with_table(table_name, fun) do
    case :ets.info(table_name) do
      :undefined -> []
      _ -> fun.()
    end
  end

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
    case :ets.info(@outbound_duration_samples) do
      :undefined ->
        {nil, nil, nil}

      _ ->
        samples =
          @outbound_duration_samples
          |> :ets.lookup(host)
          |> Enum.map(fn {^host, ms} -> ms end)
          |> Enum.sort()

        case samples do
          [] ->
            {nil, nil, nil}

          _ ->
            {percentile(samples, length(samples), 50), percentile(samples, length(samples), 95),
             percentile(samples, length(samples), 99)}
        end
    end
  end

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
    case :ets.info(@inbound_duration_samples) do
      :undefined ->
        {nil, nil, nil}

      _ ->
        samples =
          @inbound_duration_samples
          |> :ets.lookup(route_key)
          |> Enum.map(fn {^route_key, ms} -> ms end)
          |> Enum.sort()

        case samples do
          [] ->
            {nil, nil, nil}

          _ ->
            {percentile(samples, length(samples), 50), percentile(samples, length(samples), 95),
             percentile(samples, length(samples), 99)}
        end
    end
  end

  defp lookup_inbound(timestamp) do
    case :ets.lookup(@inbound_recent, timestamp) do
      [{^timestamp, event}] -> event
      [] -> nil
    end
  end

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
