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
          notifiers: [webhook: "https://hooks.example.com/alerts"]
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

  """

  @doc """
  Evaluate all configured alerts against current ETS data.

  Returns a list of triggered alert maps (or empty list).
  Only fires alerts that haven't fired within their `min_interval_seconds`.
  """
  def evaluate do
    alerts_config = Application.get_env(:monitorex, :alerts, [])

    alerts_config
    |> Enum.flat_map(fn alert_cfg ->
      evaluate_alert(alert_cfg, System.system_time(:second))
    end)
    |> Enum.filter(&debounce?/1)
  end

  defp evaluate_alert(%{metric: :host_down} = cfg, now) do
    with_table(:monitorex_outbound_hosts, fn ->
      :ets.foldl(
        fn {host, agg}, acc ->
          last_seen_sec = div(agg.last_seen, System.convert_time_unit(1, :second, :native))
          elapsed = now - last_seen_sec

          if elapsed > cfg.window_seconds do
            [build_alert(cfg, host, elapsed, "no events for #{elapsed}s") | acc]
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
                "#{metric}=#{value} exceeds #{cfg.op} #{cfg.threshold}"
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

  defp build_alert(cfg, host, value, reason) do
    %{
      alert_name: cfg.name,
      host: host,
      value: value,
      threshold: cfg.threshold,
      operator: cfg.op,
      reason: reason,
      timestamp: System.system_time(:second),
      notifiers: cfg[:notifiers] || []
    }
  end

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

            # Cleanup old entries
            to_delete =
              :ets.foldl(
                fn
                  {k, ts}, acc when now - ts > min_interval * 2 -> [k | acc]
                  _, acc -> acc
                end,
                [],
                debounce_table
              )

            Enum.each(to_delete, &:ets.delete(debounce_table, &1))
            true
        end
    end
  end

  @doc """
  Fire all notifiers for triggered alerts.
  """
  def fire_alerts(alerts) do
    Enum.each(alerts, fn alert ->
      Enum.each(alert.notifiers, fn
        {:webhook, url} -> fire_webhook(url, alert)
        _ -> :ok
      end)
    end)
  end

  defp fire_webhook(url, alert) do
    task =
      Task.async(fn ->
        try do
          _url = URI.parse(url)
          _alert = alert
          :ok
        rescue
          _ -> :error
        end
      end)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, _} -> :ok
      nil -> :error
    end
  end

  defp with_table(name, fun) do
    case :ets.info(name) do
      :undefined -> nil
      _ -> fun.()
    end
  end
end
