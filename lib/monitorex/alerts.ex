# Alerts coordinates multiple notifier backends; aliases are required.
# credo:disable-for-next-line Credo.Check.Refactor.ModuleDependencies
defmodule Monitorex.Alerts do
  @moduledoc """
  Threshold-based alert evaluation for Monitorex.

  Runs during the Collector cleanup cycle and fires notifiers when
  metrics exceed configured thresholds.  Debounce prevents repeated
  alerts within a configurable `min_interval`.

  ## Configuration

      config :monitorex, :alerts, [
        %{
          name: "High error rate",
          metric: :error_rate,
          op: :gt,
          threshold: 0.05,
          window_seconds: 300,
          min_interval_seconds: 300,
          notifiers: [
            webhook: "https://hooks.example.com/alerts",
            slack: "https://hooks.slack.com/services/...",
            discord: "https://discord.com/api/webhooks/...",
            email: "ops@example.com"
          ]
        }
      ]

  ## Supported metrics

    * `:error_rate` — host-level error rate (errors / requests, float 0.0–1.0)
    * `:avg_latency_ms` — host-level average latency in ms
    * `:p99_latency_ms` — host-level p99 latency in ms
    * `:requests_per_min` — host-level request rate
    * `:host_down` — no events from a host for `window_seconds`

  ## Supported operators

    * `:gt` — greater than threshold
    * `:lt` — less than threshold

  ## Runtime API

    * `list_rules/0` — list current alert rules
    * `add_rule/1` — add a rule at runtime
    * `remove_rule/1` — remove by name

  """

  use GenServer

  require Logger

  alias Monitorex.AlertHistory
  alias Monitorex.Notifiers.Discord
  alias Monitorex.Notifiers.Email
  alias Monitorex.Notifiers.Slack

  # ── Public API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "List all current alert rules (config + runtime)."
  @spec list_rules() :: [map()]
  def list_rules do
    GenServer.call(__MODULE__, :list_rules)
  end

  @doc "Add an alert rule at runtime."
  @spec add_rule(map()) :: :ok
  def add_rule(rule) do
    GenServer.call(__MODULE__, {:add_rule, rule})
  end

  @doc "Remove a runtime alert rule by name."
  @spec remove_rule(String.t()) :: :ok | :not_found
  def remove_rule(name) do
    GenServer.call(__MODULE__, {:remove_rule, name})
  end

  @doc """
  Evaluate all configured alerts against current ETS data.

  Returns a list of triggered alert maps (or empty list).
  Only fires alerts that haven't fired within their `min_interval_seconds`.
  """
  @spec evaluate() :: [map()]
  def evaluate do
    rules = Application.get_env(:monitorex, :alerts, [])
    now = System.system_time(:second)

    rules
    |> Enum.flat_map(fn alert_cfg ->
      evaluate_alert(alert_cfg, now)
    end)
    |> Enum.filter(&debounce?/1)
    |> tap(&record_and_fire/1)
  end

  # ── GenServer callbacks ──

  @impl true
  def init(_opts) do
    config_rules = Application.get_env(:monitorex, :alerts, [])
    {:ok, %{rules: config_rules, debounce_table: create_debounce_table()}}
  end

  @impl true
  def handle_call(:list_rules, _from, state) do
    {:reply, state.rules, state}
  end

  @impl true
  def handle_call({:add_rule, rule}, _from, state) do
    new_rules = [rule | Enum.reject(state.rules, &(&1.name == rule.name))]
    {:reply, :ok, %{state | rules: new_rules}}
  end

  @impl true
  def handle_call({:remove_rule, name}, _from, state) do
    case Enum.split_with(state.rules, &(&1.name == name)) do
      {[], _rest} -> {:reply, :not_found, state}
      {_removed, rest} -> {:reply, :ok, %{state | rules: rest}}
    end
  end

  # ── Evaluation ──

  defp evaluate_alert(%{metric: :host_down} = cfg, now) do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc ->
          last_seen_sec = div(agg.last_seen, System.convert_time_unit(1, :second, :native))
          elapsed = now - last_seen_sec

          if elapsed > cfg.window_seconds do
            [build_alert(cfg, host, elapsed, :host_down, "no events for #{elapsed}s") | acc]
          else
            acc
          end
        end,
        [],
        :monitorex_outbound_hosts
      )
    end) || []
  end

  defp evaluate_alert(%{metric: metric} = cfg, _now)
       when metric in [:error_rate, :avg_latency_ms, :p99_latency_ms, :requests_per_min] do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc ->
          value = extract_metric(agg, metric)

          if value != nil and compare(value, cfg.op, cfg.threshold) do
            [
              build_alert(
                cfg,
                host,
                value,
                metric,
                "#{metric}=#{format_value(value)} exceeds #{cfg.op} #{format_value(cfg.threshold)}"
              )
              | acc
            ]
          else
            acc
          end
        end,
        [],
        :monitorex_outbound_hosts
      )
    end) || []
  end

  defp evaluate_alert(_cfg, _now), do: []

  defp extract_metric(agg, :error_rate) do
    if agg.requests > 0, do: agg.errors / agg.requests, else: nil
  end

  defp extract_metric(agg, :avg_latency_ms) do
    if agg.requests > 0, do: agg.total_duration / agg.requests, else: nil
  end

  defp extract_metric(agg, :p99_latency_ms), do: agg[:p99]

  defp extract_metric(agg, :requests_per_min), do: agg.requests

  defp compare(value, :gt, threshold), do: value > threshold
  defp compare(value, :lt, threshold), do: value < threshold

  defp build_alert(cfg, host, value, metric, reason) do
    %{
      alert_name: cfg.name,
      host: host,
      value: value,
      threshold: cfg.threshold,
      operator: cfg.op,
      reason: reason,
      timestamp: System.system_time(:second),
      notifiers: cfg[:notifiers] || [],
      metric: metric,
      status: :firing,
      acknowledged_at: nil,
      snoozed_until: nil,
      id: System.system_time(:microsecond)
    }
  end

  # ── Debounce ──

  defp debounce?(alert) do
    debounce_table = :monitorex_alert_debounce
    key = {alert.alert_name, alert.host}
    min_interval = Application.get_env(:monitorex, :alert_min_interval_seconds, 300)
    now = System.system_time(:second)

    case :ets.info(debounce_table) do
      :undefined ->
        :ets.new(debounce_table, [:public, :named_table, :set])
        :ets.insert(debounce_table, {key, now})
        true

      _ ->
        case :ets.lookup(debounce_table, key) do
          [{^key, last_fired}] when now - last_fired < min_interval ->
            false

          _ ->
            :ets.insert(debounce_table, {key, now})
            prune_debounce(debounce_table, now, min_interval)
            true
        end
    end
  end

  defp prune_debounce(table, now, min_interval) do
    to_delete =
      :ets.foldl(
        fn
          {k, ts}, acc when now - ts > min_interval * 2 -> [k | acc]
          _, acc -> acc
        end,
        [],
        table
      )

    Enum.each(to_delete, &:ets.delete(table, &1))
  end

  # ── Record & Fire ──

  defp record_and_fire(alerts) do
    Enum.each(alerts, fn alert ->
      # Record in history (best-effort if GenServer not running)
      try do
        AlertHistory.record_alert(alert)
      catch
        :exit, {:noproc, _} -> :ok
      end

      # Fire notifiers
      Enum.each(alert.notifiers, fn
        {:webhook, url} ->
          fire_webhook(url, alert)

        {:slack, url} ->
          Task.start(fn -> Slack.notify(alert, url) end)

        {:discord, url} ->
          Task.start(fn -> Discord.notify(alert, url) end)

        {:email, config} ->
          Task.start(fn -> Email.notify(alert, config) end)

        _ ->
          :ok
      end)
    end)
  end

  @dialyzer {:no_return, record_and_fire: 1}

  defp fire_webhook(url, alert) do
    Task.start(fn ->
      try do
        headers = [{"content-type", "application/json"}]
        body = Jason.encode!(sanitize_alert(alert))

        case :hackney.post(url, headers, body, [:with_body, timeout: 10_000]) do
          {:ok, status, _hdrs, _resp} when status in 200..299 -> :ok
          {:ok, status, _, _} -> Logger.warning("Webhook #{url} returned #{status}")
          {:error, reason} -> Logger.warning("Webhook #{url} failed: #{inspect(reason)}")
        end
      rescue
        e -> Logger.warning("Webhook exception: #{inspect(e)}")
      end
    end)
  end

  @dialyzer {:no_return, fire_webhook: 2}

  # ── Helpers ──

  defp create_debounce_table do
    table = :monitorex_alert_debounce

    case :ets.info(table) do
      :undefined -> :ets.new(table, [:public, :named_table, :set])
      _ -> table
    end
  end

  defp with_table(name, fun) do
    case :ets.info(name) do
      :undefined -> nil
      _ -> fun.()
    end
  end

  defp sanitize_alert(alert) do
    Map.drop(alert, [:notifiers, :status, :acknowledged_at, :snoozed_until, :id])
  end

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: to_string(v)
end
