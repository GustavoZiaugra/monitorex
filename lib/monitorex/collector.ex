# Collector orchestrates telemetry and storage; aliases are all required.
# credo:disable-for-next-line Credo.Check.Refactor.ModuleDependencies
defmodule Monitorex.Collector do
  @moduledoc """
  GenServer that owns ETS tables, attaches telemetry handlers, and runs
  periodic maintenance for the Monitorex monitoring system.

  Event data is written through the configured storage backend
  (`Monitorex.Storage.Backend`).  By default this is `Monitorex.Storage.ETS`,
  which writes to the ETS tables created here.
  """

  use GenServer

  alias Monitorex.Alerts
  alias Monitorex.Collector.Handlers

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
  Handles a telemetry event by writing it through the storage backend.
  Called by telemetry handlers.
  """
  def handle_event(%Monitorex.Event{} = event, pid \\ __MODULE__) do
    GenServer.cast(pid, {:handle_event, event})
  end

  # ── Helpers ──

  defp backend do
    Application.get_env(:monitorex, :storage_backend, Monitorex.Storage.ETS)
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
    event = truncate_bodies(event)

    # Dedup check for Tesla-over-Finch
    if event.dedup_key && state.dedup do
      case :ets.insert_new(state.dedup, {event.dedup_key, System.monotonic_time()}) do
        false -> :ignored
        true -> backend().record_event(event)
      end
    else
      backend().record_event(event)
    end

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
        &Handlers.tesla/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :tesla_exception},
        [:tesla, :request, :exception],
        &Handlers.tesla/4,
        nil
      )
    end

    if :finch in sources do
      :telemetry.attach(
        {Monitorex.Collector, :finch},
        [:finch, :request, :stop],
        &Handlers.finch/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :finch_exception},
        [:finch, :request, :exception],
        &Handlers.finch/4,
        nil
      )
    end

    if :req in sources do
      :telemetry.attach(
        {Monitorex.Collector, :req},
        [:req, :request, :pipeline, :stop],
        &Handlers.req/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :req_exception},
        [:req, :request, :pipeline, :error],
        &Handlers.req/4,
        nil
      )
    end

    if :phoenix in sources do
      :telemetry.attach(
        {Monitorex.Collector, :phoenix},
        [:phoenix, :router_dispatch, :stop],
        &Handlers.phoenix/4,
        nil
      )

      :telemetry.attach(
        {Monitorex.Collector, :phoenix_exception},
        [:phoenix, :router_dispatch, :exception],
        &Handlers.phoenix/4,
        nil
      )
    end
  end

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

  defp perform_cleanup(_state) do
    backend().prune()

    # Evaluate alert thresholds
    Alerts.evaluate()
  end

  # ── Health check ──

  defp verify_handlers(state) do
    sources = state.sources

    if :tesla in sources do
      safe_reattach(
        {Monitorex.Collector, :tesla},
        [:tesla, :request, :stop],
        &Handlers.tesla/4
      )
    end

    if :finch in sources do
      safe_reattach(
        {Monitorex.Collector, :finch},
        [:finch, :request, :stop],
        &Handlers.finch/4
      )
    end

    if :req in sources do
      safe_reattach(
        {Monitorex.Collector, :req},
        [:req, :request, :pipeline, :stop],
        &Handlers.req/4
      )
    end

    if :phoenix in sources do
      safe_reattach(
        {Monitorex.Collector, :phoenix},
        [:phoenix, :router_dispatch, :stop],
        &Handlers.phoenix/4
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
end
