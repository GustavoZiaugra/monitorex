defmodule Monitorex.AlertsTest do
  use ExUnit.Case, async: false

  alias Monitorex.Alerts

  setup do
    Enum.each(
      [
        :monitorex_outbound_hosts,
        :monitorex_outbound_endpoints,
        :monitorex_outbound_recent,
        :monitorex_outbound_duration_samples,
        :monitorex_inbound_routes,
        :monitorex_inbound_consumers,
        :monitorex_inbound_recent,
        :monitorex_inbound_duration_samples,
        :monitorex_slow_outbound,
        :monitorex_slow_inbound,
        :monitorex_alert_debounce
      ],
      fn table ->
        try do
          :ets.delete(table)
        rescue
          _ -> :ok
        end
      end
    )

    :ok
  end

  defp seed_hosts(hosts_data) do
    :ets.new(:monitorex_outbound_hosts, [:public, :named_table, :set])

    Enum.each(hosts_data, fn {host, agg} ->
      :ets.insert(:monitorex_outbound_hosts, {host, agg})
    end)
  end

  describe "evaluate/0" do
    test "returns empty list when no alerts configured" do
      assert Alerts.evaluate() == []
    end

    test "triggers alert when error_rate exceeds threshold" do
      seed_hosts([
        {"api.bad.com",
         %{requests: 100, errors: 30, total_duration: 5000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High error rate",
          metric: :error_rate,
          op: :gt,
          threshold: 0.05,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      assert hd(alerts).alert_name == "High error rate"
      assert hd(alerts).host == "api.bad.com"
      assert hd(alerts).value > 0.05

      Application.delete_env(:monitorex, :alerts)
    end

    test "triggers alert when avg_latency exceeds threshold" do
      seed_hosts([
        {"api.slow.com",
         %{requests: 10, errors: 0, total_duration: 50_000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High latency",
          metric: :avg_latency_ms,
          op: :gt,
          threshold: 1000.0,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      # avg = 50000 / 10 = 5000ms, threshold is 1000ms
      assert hd(alerts).value > 1000.0

      Application.delete_env(:monitorex, :alerts)
    end

    test "does not trigger when metric is below threshold" do
      seed_hosts([
        {"api.healthy.com",
         %{requests: 100, errors: 1, total_duration: 3000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High error rate",
          metric: :error_rate,
          op: :gt,
          threshold: 0.05,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert alerts == []

      Application.delete_env(:monitorex, :alerts)
    end

    test "host_down triggers when last_seen exceeds window" do
      seed_hosts([
        {"api.dead.com",
         %{
           requests: 5,
           errors: 0,
           total_duration: 500.0,
           last_seen: System.monotonic_time() - System.convert_time_unit(600, :second, :native)
         }}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "Host down",
          metric: :host_down,
          op: :gt,
          threshold: 300,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      assert hd(alerts).alert_name == "Host down"

      Application.delete_env(:monitorex, :alerts)
    end

    test "debounce prevents duplicate alerts within min_interval" do
      seed_hosts([
        {"api.noisy.com",
         %{requests: 100, errors: 50, total_duration: 5000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High error rate",
          metric: :error_rate,
          op: :gt,
          threshold: 0.05,
          window_seconds: 300,
          min_interval_seconds: 60
        }
      ])

      first = Alerts.evaluate()
      assert length(first) == 1

      second = Alerts.evaluate()
      assert second == [], "debounce should suppress within interval"

      Application.delete_env(:monitorex, :alerts)
    end

    test "evaluates multiple hosts independently" do
      now = System.monotonic_time()

      seed_hosts([
        {"api.bad.com", %{requests: 100, errors: 30, total_duration: 5000.0, last_seen: now}},
        {"api.good.com", %{requests: 100, errors: 1, total_duration: 3000.0, last_seen: now}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High error rate",
          metric: :error_rate,
          op: :gt,
          threshold: 0.05,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      assert hd(alerts).host == "api.bad.com"

      Application.delete_env(:monitorex, :alerts)
    end
  end
end
