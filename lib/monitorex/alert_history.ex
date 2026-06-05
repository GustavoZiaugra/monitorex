defmodule Monitorex.AlertHistory do
  @moduledoc """
  GenServer that manages an append-only ETS log of fired alerts.

  Provides query, acknowledge, snooze, and active-alert-count functions
  used by the dashboard UI and the alert evaluation engine.
  """

  use GenServer

  @table :monitorex_alerts_history
  @default_max_entries 1_000

  # ── Public API ──

  @doc "Start the AlertHistory GenServer."
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Record a fired alert into the history table."
  @spec record_alert(map()) :: :ok
  def record_alert(alert) do
    GenServer.call(__MODULE__, {:record, alert})
  end

  @doc """
  List alert history entries, newest first.

  ## Options

    * `:limit` — max entries (default: 100)
    * `:status` — filter by `:firing`, `:acknowledged`, `:snoozed`, or `:all`
    * `:metric` — filter by metric atom
  """
  @spec list_history(keyword()) :: [map()]
  def list_history(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    status_filter = Keyword.get(opts, :status, :all)
    metric_filter = Keyword.get(opts, :metric, :all)

    with_table(fn ->
      entries =
        :ets.tab2list(@table)
        |> Enum.reverse()
        |> Enum.map(fn {_ts, entry} -> entry end)
        |> maybe_filter_status(status_filter)
        |> maybe_filter_metric(metric_filter)
        |> Enum.take(limit)

      entries
    end) || []
  end

  @doc "Count of currently firing (unacknowledged, non-snoozed) alerts."
  @spec firing_count() :: non_neg_integer()
  def firing_count do
    with_table(fn ->
      :ets.tab2list(@table)
      |> Enum.count(fn {_ts, entry} -> entry.status == :firing end)
    end) || 0
  end

  @doc "Acknowledge an alert by its timestamp key."
  @spec acknowledge(integer()) :: :ok | :not_found
  def acknowledge(timestamp) do
    GenServer.call(__MODULE__, {:update_status, timestamp, :acknowledged})
  end

  @doc "Snooze an alert by its timestamp key."
  @spec snooze(integer(), snooze_seconds :: pos_integer()) :: :ok | :not_found
  def snooze(timestamp, snooze_seconds) do
    GenServer.call(__MODULE__, {:snooze, timestamp, snooze_seconds})
  end

  @doc """
  Re-evaluate snoozed alerts: any whose snooze has expired become `:firing` again.
  Called automatically by the AlertHistory cleanup cycle.
  """
  @spec expire_snoozes() :: :ok
  def expire_snoozes do
    GenServer.call(__MODULE__, :expire_snoozes)
  end

  @doc "Clear old entries beyond `:max_alert_history` (default 1_000)."
  @spec trim() :: :ok
  def trim do
    GenServer.call(__MODULE__, :trim)
  end

  # ── GenServer callbacks ──

  @impl true
  def init(_opts) do
    create_table()
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:record, alert}, _from, state) do
    :ets.insert(@table, {alert.id, alert})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update_status, id, new_status}, _from, state) do
    reply =
      case :ets.lookup(@table, id) do
        [{^id, entry}] ->
          updated =
            case new_status do
              :acknowledged ->
                %{entry | status: :acknowledged, acknowledged_at: System.system_time(:second)}

              _ ->
                %{entry | status: new_status}
            end

          :ets.insert(@table, {id, updated})
          :ok

        [] ->
          :not_found
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:snooze, id, seconds}, _from, state) do
    until = System.system_time(:second) + seconds

    reply =
      case :ets.lookup(@table, id) do
        [{^id, entry}] ->
          :ets.insert(@table, {id, %{entry | status: :snoozed, snoozed_until: until}})
          :ok

        [] ->
          :not_found
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:expire_snoozes, _from, state) do
    now = System.system_time(:second)

    :ets.foldl(
      fn
        {id, %{status: :snoozed, snoozed_until: until}}, _acc when until <= now ->
          [{^id, entry}] = :ets.lookup(@table, id)
          :ets.insert(@table, {id, %{entry | status: :firing, snoozed_until: nil}})

        _, _acc ->
          :ok
      end,
      :ok,
      @table
    )

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:trim, _from, state) do
    max_entries = Application.get_env(:monitorex, :max_alert_history, @default_max_entries)
    count = :ets.info(@table, :size)

    if is_integer(count) and count > max_entries do
      to_delete = count - max_entries

      keys =
        :ets.foldl(
          fn
            {key, _}, acc when length(acc) < to_delete -> [key | acc]
            _, acc -> acc
          end,
          [],
          @table
        )

      Enum.each(keys, &:ets.delete(@table, &1))
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    expire_snoozes()
    trim()
    schedule_cleanup()
    {:noreply, state}
  end

  # ── Private ──

  defp create_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:public, :named_table, :ordered_set, read_concurrency: true])

      _ ->
        :ets.delete_all_objects(@table)
    end
  end

  defp schedule_cleanup do
    interval = Application.get_env(:monitorex, :alert_cleanup_interval_ms, 60_000)
    Process.send_after(self(), :cleanup, interval)
  end

  defp with_table(fun) do
    case :ets.info(@table) do
      :undefined -> nil
      _ -> fun.()
    end
  end

  defp maybe_filter_status(entries, :all), do: entries
  defp maybe_filter_status(entries, status), do: Enum.filter(entries, &(&1.status == status))

  defp maybe_filter_metric(entries, :all), do: entries
  defp maybe_filter_metric(entries, metric), do: Enum.filter(entries, &(&1.metric == metric))
end
