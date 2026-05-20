defmodule Monitorex.Collector do
  @moduledoc """
  GenServer that owns ETS tables, attaches telemetry handlers, and runs
  periodic maintenance for the Monitorex monitoring system.
  """

  use GenServer

  # ── ETS table names ──

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

  @dedup :monitorex_dedup

  @default_max_recent 500
  @default_max_recent_inbound 500
  @default_max_slow 200
  @default_max_endpoints 2_000
  @default_endpoint_ttl :timer.hours(1)
  @default_cleanup_interval 5_000
  @default_health_check_interval 30_000
  @default_sources [:tesla, :finch, :req, :phoenix]

  # ── Public API ──

  @doc """
  Starts the Collector GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Handles a telemetry event by writing it to the appropriate ETS tables.
  Called by telemetry handlers.
  """
  def handle_event(%Monitorex.Event{} = event, pid \\ __MODULE__) do
    GenServer.cast(pid, {:handle_event, event})
  end

  # ── Callbacks ──

  @impl true
  def init(_opts) do
    tables = create_tables()
    sources = Application.get_env(:monitorex, :sources, @default_sources)
    attach_telemetry_handlers(sources)

    schedule_cleanup()
    schedule_health_check()

    {:ok, Map.merge(tables, %{sources: sources})}
  end

  @impl true
  def handle_cast({:handle_event, event}, state) do
    write_event(event, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup(state)
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    verify_handlers(state)
    schedule_health_check()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach({Monitorex.Collector, :tesla})
    :telemetry.detach({Monitorex.Collector, :finch})
    :telemetry.detach({Monitorex.Collector, :req})
    :telemetry.detach({Monitorex.Collector, :phoenix})

    tables = [
      :monitorex_outbound_hosts,
      :monitorex_outbound_endpoints,
      :monitorex_outbound_recent,
      :monitorex_outbound_duration_samples,
      :monitorex_inbound_routes,
      :monitorex_inbound_consumers,
      :monitorex_inbound_recent,
      :monitorex_inbound_duration_samples,
      :monitorex_slow_outbound,
      :monitorex_slow_inbound
    ]

    # Add dedup table if it was created
    dedup_tables = if state.dedup, do: [state.dedup], else: []

    Enum.each(tables ++ dedup_tables, fn table when is_atom(table) ->
      try do
        :ets.delete(table)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  # ── Table creation ──

  defp create_tables do
    :ets.new(@outbound_hosts, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@outbound_endpoints, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@outbound_recent, [:public, :named_table, :ordered_set, read_concurrency: true])
    :ets.new(@outbound_duration_samples, [:public, :named_table, :bag, read_concurrency: true])

    :ets.new(@inbound_routes, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@inbound_consumers, [:public, :named_table, :set, read_concurrency: true])
    :ets.new(@inbound_recent, [:public, :named_table, :ordered_set, read_concurrency: true])
    :ets.new(@inbound_duration_samples, [:public, :named_table, :bag, read_concurrency: true])

    # Slow request tables (separate from recent — longer retention)
    :ets.new(@outbound_slow, [:public, :named_table, :ordered_set, read_concurrency: true])
    :ets.new(@inbound_slow, [:public, :named_table, :ordered_set, read_concurrency: true])

    clients = Application.get_env(:monitorex, :clients, [])

    dedup_table =
      if :tesla in clients and :finch in clients do
        :ets.new(@dedup, [:public, :named_table, :set, read_concurrency: true])
        @dedup
      end

    %{
      outbound_hosts: @outbound_hosts,
      outbound_endpoints: @outbound_endpoints,
      outbound_recent: @outbound_recent,
      outbound_duration_samples: @outbound_duration_samples,
      inbound_routes: @inbound_routes,
      inbound_consumers: @inbound_consumers,
      inbound_recent: @inbound_recent,
      inbound_duration_samples: @inbound_duration_samples,
      outbound_slow: @outbound_slow,
      inbound_slow: @inbound_slow,
      dedup: dedup_table
    }
  end

  # ── Telemetry attachment ──

  defp attach_telemetry_handlers(sources) do
    if :tesla in sources do
      :telemetry.attach(
        {Monitorex.Collector, :tesla},
        [:tesla, :request, :stop],
        &Monitorex.Collector.Handlers.tesla/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :tesla_exception},
        [:tesla, :request, :exception],
        &Monitorex.Collector.Handlers.tesla/4,
        nil
      )
    end

    if :finch in sources do
      :telemetry.attach(
        {Monitorex.Collector, :finch},
        [:finch, :request, :stop],
        &Monitorex.Collector.Handlers.finch/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :finch_exception},
        [:finch, :request, :exception],
        &Monitorex.Collector.Handlers.finch/4,
        nil
      )
    end

    if :req in sources do
      :telemetry.attach(
        {Monitorex.Collector, :req},
        [:req, :request, :pipeline, :stop],
        &Monitorex.Collector.Handlers.req/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :req_exception},
        [:req, :request, :pipeline, :error],
        &Monitorex.Collector.Handlers.req/4,
        nil
      )
    end

    if :phoenix in sources do
      :telemetry.attach(
        {Monitorex.Collector, :phoenix},
        [:phoenix, :router_dispatch, :stop],
        &Monitorex.Collector.Handlers.phoenix/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :phoenix_exception},
        [:phoenix, :router_dispatch, :exception],
        &Monitorex.Collector.Handlers.phoenix/4,
        nil
      )
    end
  end

  # ── Event writing ──

  defp write_event(%Monitorex.Event{} = event, state) do
    event = truncate_bodies(event)

    # Dedup check for Tesla-over-Finch
    if event.dedup_key && state.dedup do
      case :ets.insert_new(state.dedup, {event.dedup_key, System.monotonic_time()}) do
        false -> :ignored
        true -> do_write(event, state)
      end
    else
      do_write(event, state)
    end
  end

  defp do_write(event, state) do
    case event.direction do
      :outbound -> write_outbound(event, state)
      :inbound -> write_inbound(event, state)
    end
  end

  # ── Outbound writes ──

  defp write_outbound(event, state) do
    host = event.host || "unknown"

    # Host aggregate
    update_host(host, event, state)

    # Endpoint aggregate
    endpoint_key = {host, event.path}
    update_endpoint(endpoint_key, event, state)

    # Recent ring buffer
    ts = System.system_time(:microsecond)
    :ets.insert(state.outbound_recent, {ts, event})

    # Duration sample
    if event.duration_ms do
      :ets.insert(state.outbound_duration_samples, {host, event.duration_ms})
    end

    # Slow request table
    if event.slow do
      :ets.insert(state.outbound_slow, {ts, event})
    end
  end

  defp update_host(host, event, state) do
    case :ets.lookup(state.outbound_hosts, host) do
      [{^host, agg}] ->
        :ets.insert(state.outbound_hosts, {host, increment_aggregate(agg, event)})

      [] ->
        :ets.insert(state.outbound_hosts, {host, new_aggregate(event)})
    end
  end

  defp update_endpoint(key, event, state) do
    case :ets.lookup(state.outbound_endpoints, key) do
      [{^key, agg}] ->
        :ets.insert(state.outbound_endpoints, {key, increment_aggregate(agg, event)})

      [] ->
        :ets.insert(state.outbound_endpoints, {key, new_aggregate(event)})
    end
  end

  # ── Inbound writes ──

  defp write_inbound(event, state) do
    route_key = "#{event.method}:#{event.path}"

    # Route aggregate
    update_route(route_key, event, state)

    # Consumer aggregate
    if event.consumer do
      update_consumer(event.consumer, event, state)
    end

    # Recent ring buffer
    ts = System.system_time(:microsecond)
    :ets.insert(state.inbound_recent, {ts, event})

    # Duration sample
    if event.duration_ms do
      :ets.insert(state.inbound_duration_samples, {route_key, event.duration_ms})
    end

    # Slow request table
    if event.slow do
      :ets.insert(state.inbound_slow, {ts, event})
    end
  end

  defp update_route(route_key, event, state) do
    case :ets.lookup(state.inbound_routes, route_key) do
      [{^route_key, agg}] ->
        :ets.insert(state.inbound_routes, {route_key, increment_aggregate(agg, event)})

      [] ->
        :ets.insert(state.inbound_routes, {route_key, new_aggregate(event)})
    end
  end

  defp update_consumer(consumer, event, state) do
    case :ets.lookup(state.inbound_consumers, consumer) do
      [{^consumer, agg}] ->
        :ets.insert(state.inbound_consumers, {consumer, increment_aggregate(agg, event)})

      [] ->
        :ets.insert(state.inbound_consumers, {consumer, new_aggregate(event)})
    end
  end

  # ── Aggregate helpers ──

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

  defp schedule_cleanup do
    interval = Application.get_env(:monitorex, :cleanup_interval_ms, @default_cleanup_interval)
    Process.send_after(self(), :cleanup, interval)
  end

  defp schedule_health_check do
    interval =
      Application.get_env(:monitorex, :health_check_interval_ms, @default_health_check_interval)

    Process.send_after(self(), :health_check, interval)
  end

  # ── Cleanup ──

  defp perform_cleanup(state) do
    max_recent = Application.get_env(:monitorex, :max_recent, @default_max_recent)

    max_recent_inbound =
      Application.get_env(:monitorex, :max_recent_inbound, @default_max_recent_inbound)

    max_endpoints = Application.get_env(:monitorex, :max_endpoints, @default_max_endpoints)
    endpoint_ttl = Application.get_env(:monitorex, :endpoint_ttl, @default_endpoint_ttl)
    wall_now = System.system_time(:microsecond)
    mono_now = System.monotonic_time()

    # Trim outbound recent
    trim_recent(state.outbound_recent, max_recent)

    # Trim inbound recent
    trim_recent(state.inbound_recent, max_recent_inbound)

    # Prune stale endpoints
    prune_stale_endpoints(state, wall_now, endpoint_ttl)

    # Cap aggregate tables to prevent unbounded growth during traffic spikes
    trim_aggregate(state.outbound_hosts, max_endpoints)
    trim_aggregate(state.outbound_endpoints, max_endpoints)
    trim_aggregate(state.inbound_routes, max_endpoints)
    trim_aggregate(state.inbound_consumers, max_endpoints)

    # Trim slow request tables
    max_slow = Application.get_env(:monitorex, :max_slow, @default_max_slow)
    trim_recent(state.outbound_slow, max_slow)
    trim_recent(state.inbound_slow, max_slow)

    # Compute percentiles and update aggregates
    compute_percentiles(state, :outbound)
    compute_percentiles(state, :inbound)

    # Prune dedup table
    if state.dedup do
      prune_dedup(state.dedup, mono_now)
    end
  end

  defp trim_recent(table, max) do
    count = :ets.info(table, :size)

    if is_integer(count) and count > max do
      to_delete = count - max
      # Ordered set: first N entries (oldest) to delete
      first_keys =
        :ets.foldl(
          fn
            {key, _}, acc when length(acc) < to_delete -> [key | acc]
            _other, acc -> acc
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
      # Aggregate tables are :set; sort by last_seen and drop oldest
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

  defp prune_stale_endpoints(state, wall_now, ttl) do
    prune_set(state.outbound_hosts, wall_now, ttl)
    prune_set(state.outbound_endpoints, wall_now, ttl)
    prune_set(state.inbound_routes, wall_now, ttl)
    prune_set(state.inbound_consumers, wall_now, ttl)
  end

  defp prune_set(table, wall_now, ttl_ms) do
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

  defp compute_percentiles(state, :outbound) do
    # Grab all unique hosts
    hosts =
      :ets.foldl(fn {host, _}, acc -> [host | acc] end, [], state.outbound_hosts)
      |> Enum.uniq()

    Enum.each(hosts, fn host ->
      samples =
        :ets.lookup(state.outbound_duration_samples, host)
        |> Enum.map(fn {^host, ms} -> ms end)
        |> Enum.sort()

      if length(samples) >= 10 do
        {p50, p95, p99} = compute_percentile_values(samples)

        case :ets.lookup(state.outbound_hosts, host) do
          [{^host, agg}] ->
            :ets.insert(
              state.outbound_hosts,
              {host, Map.merge(agg, %{p50: p50, p95: p95, p99: p99})}
            )

          _ ->
            :ok
        end

        # Clear samples after computing
        :ets.delete(state.outbound_duration_samples, host)
      end
    end)
  end

  defp compute_percentiles(state, :inbound) do
    routes =
      :ets.foldl(fn {key, _}, acc -> [key | acc] end, [], state.inbound_routes)
      |> Enum.uniq()

    Enum.each(routes, fn route_key ->
      samples =
        :ets.lookup(state.inbound_duration_samples, route_key)
        |> Enum.map(fn {^route_key, ms} -> ms end)
        |> Enum.sort()

      if length(samples) >= 10 do
        {p50, p95, p99} = compute_percentile_values(samples)

        case :ets.lookup(state.inbound_routes, route_key) do
          [{^route_key, agg}] ->
            :ets.insert(
              state.inbound_routes,
              {route_key, Map.merge(agg, %{p50: p50, p95: p95, p99: p99})}
            )

          _ ->
            :ok
        end

        :ets.delete(state.inbound_duration_samples, route_key)
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

  defp prune_dedup(dedup_table, now) do
    dedup_ttl_ms = Application.get_env(:monitorex, :dedup_ttl, :timer.seconds(60))

    to_delete =
      :ets.foldl(
        fn {key, ts}, acc ->
          elapsed_ms = System.convert_time_unit(now - ts, :native, :millisecond)
          if elapsed_ms > dedup_ttl_ms, do: [key | acc], else: acc
        end,
        [],
        dedup_table
      )

    Enum.each(to_delete, &:ets.delete(dedup_table, &1))
  end

  # ── Health check ──

  defp verify_handlers(state) do
    sources = state.sources

    if :tesla in sources do
      safe_reattach(
        {Monitorex.Collector, :tesla},
        [:tesla, :request, :stop],
        &Monitorex.Collector.Handlers.tesla/4
      )
    end

    if :finch in sources do
      safe_reattach(
        {Monitorex.Collector, :finch},
        [:finch, :request, :stop],
        &Monitorex.Collector.Handlers.finch/4
      )
    end

    if :req in sources do
      safe_reattach(
        {Monitorex.Collector, :req},
        [:req, :request, :pipeline, :stop],
        &Monitorex.Collector.Handlers.req/4
      )
    end

    if :phoenix in sources do
      safe_reattach(
        {Monitorex.Collector, :phoenix},
        [:phoenix, :router_dispatch, :stop],
        &Monitorex.Collector.Handlers.phoenix/4
      )
    end
  end

  defp safe_reattach(handler_id, event_name, handler_fn) do
    try do
      :telemetry.detach(handler_id)
    rescue
      _ -> :ok
    end

    try do
      :telemetry.attach(handler_id, event_name, handler_fn, nil)
    rescue
      _ -> :ok
    end
  end

  # These ensure EventHandler results are forwarded to the Collector via
  # Monitorex.Collector.Handlers (separate module avoids telemetry "local function" warning).
end
