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

  describe "list_rules/0, add_rule/1, remove_rule/1" do
    test "add_rule adds a runtime rule" do
      assert :ok = Alerts.add_rule(%{name: "Runtime", metric: :error_rate, op: :gt, threshold: 0.1})
      rules = Alerts.list_rules()
      assert Enum.any?(rules, &(&1.name == "Runtime"))

      # Clean up
      Alerts.remove_rule("Runtime")
    end

    test "add_rule replaces rule with same name" do
      Alerts.add_rule(%{name: "Dup", metric: :error_rate, op: :gt, threshold: 0.1})
      Alerts.add_rule(%{name: "Dup", metric: :error_rate, op: :gt, threshold: 0.2})
      rules = Alerts.list_rules()
      assert length(Enum.filter(rules, &(&1.name == "Dup"))) == 1

      Alerts.remove_rule("Dup")
    end

    test "remove_rule deletes a runtime rule" do
      Alerts.add_rule(%{name: "ToRemove", metric: :error_rate, op: :gt, threshold: 0.1})
      assert :ok = Alerts.remove_rule("ToRemove")
      refute Enum.any?(Alerts.list_rules(), &(&1.name == "ToRemove"))
    end

    test "remove_rule returns :not_found for unknown rule" do
      assert :not_found = Alerts.remove_rule("missing")
    end
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

    test "triggers alert when p99 latency exceeds threshold" do
      seed_hosts([
        {"api.slow.com",
         %{requests: 10, errors: 0, total_duration: 1000.0, p50: 50.0, p95: 90.0, p99: 2500.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High p99 latency",
          metric: :p99_latency_ms,
          op: :gt,
          threshold: 1000.0,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      assert hd(alerts).metric == :p99_latency_ms

      Application.delete_env(:monitorex, :alerts)
    end

    test "triggers alert when requests_per_min exceeds threshold" do
      seed_hosts([
        {"api.busy.com", %{requests: 500, errors: 0, total_duration: 1000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High rps",
          metric: :requests_per_min,
          op: :gt,
          threshold: 100,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      assert hd(alerts).metric == :requests_per_min

      Application.delete_env(:monitorex, :alerts)
    end

    test "supports less-than operator" do
      seed_hosts([
        {"api.quiet.com", %{requests: 5, errors: 0, total_duration: 5000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "Low traffic",
          metric: :requests_per_min,
          op: :lt,
          threshold: 100,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      alerts = Alerts.evaluate()
      assert length(alerts) == 1
      assert hd(alerts).operator == :lt

      Application.delete_env(:monitorex, :alerts)
    end

    test "webhook notifier fires asynchronously" do
      seed_hosts([
        {"api.bad.com", %{requests: 100, errors: 50, total_duration: 5000.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "High error rate",
          metric: :error_rate,
          op: :gt,
          threshold: 0.05,
          window_seconds: 300,
          min_interval_seconds: 1,
          notifiers: [webhook: "http://localhost:9999/hook"]
        }
      ])

      # Just verify evaluate does not crash with webhook notifier configured.
      alerts = Alerts.evaluate()
      assert length(alerts) == 1

      Application.delete_env(:monitorex, :alerts)
    end

    test "webhook handles 2xx, non-2xx and error responses" do
      seed_hosts([
        {"api.bad.com", %{requests: 100, errors: 50, total_duration: 5000.0, last_seen: System.monotonic_time()}}
      ])

      for {label, response} <- [
            {"2xx", {:ok, 200, [], "ok"}},
            {"4xx", {:ok, 404, [], "not found"}},
            {"error", {:error, :econnrefused}}
          ] do
        :meck.new(:hackney, [:unstick, :passthrough])
        :meck.expect(:hackney, :post, fn _, _, _, _ -> response end)

        Application.put_env(:monitorex, :alerts, [
          %{
            name: "High error rate #{label}",
            metric: :error_rate,
            op: :gt,
            threshold: 0.05,
            window_seconds: 300,
            min_interval_seconds: 1,
            notifiers: [webhook: "http://localhost:9999/hook"]
          }
        ])

        assert length(Alerts.evaluate()) == 1

        Application.delete_env(:monitorex, :alerts)
        :meck.unload(:hackney)

        # Reset debounce table between iterations
        try do
          :ets.delete_all_objects(:monitorex_alert_debounce)
        rescue
          _ -> :ok
        end
      end
    end

    test "slack notifier starts notification task" do
      assert_notifier_fires(Monitorex.Notifiers.Slack, :slack)
    end

    test "discord notifier starts notification task" do
      assert_notifier_fires(Monitorex.Notifiers.Discord, :discord)
    end

    test "email notifier starts notification task" do
      assert_notifier_fires(Monitorex.Notifiers.Email, :email)
    end

    test "evaluate handles unknown metric gracefully" do
      seed_hosts([
        {"api.example.com", %{requests: 10, errors: 0, total_duration: 100.0, last_seen: System.monotonic_time()}}
      ])

      Application.put_env(:monitorex, :alerts, [
        %{
          name: "Unknown",
          metric: :unknown_metric,
          op: :gt,
          threshold: 1,
          window_seconds: 300,
          min_interval_seconds: 1
        }
      ])

      assert Alerts.evaluate() == []
      Application.delete_env(:monitorex, :alerts)
    end

    test "evaluate handles missing outbound hosts table" do
      try do
        :ets.delete(:monitorex_outbound_hosts)
      rescue
        _ -> :ok
      end

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

      assert Alerts.evaluate() == []
      Application.delete_env(:monitorex, :alerts)
    end
  end

  defp assert_notifier_fires(module, key) do
    seed_hosts([
      {"api.#{key}.com", %{requests: 100, errors: 50, total_duration: 5000.0, last_seen: System.monotonic_time()}}
    ])

    :meck.new(module, [:unstick, :passthrough])
    :meck.expect(module, :notify, fn _alert, _config -> :ok end)

    Application.put_env(:monitorex, :alerts, [
      %{
        name: "Notifier #{key}",
        metric: :error_rate,
        op: :gt,
        threshold: 0.05,
        window_seconds: 300,
        min_interval_seconds: 1,
        notifiers: [{key, "config"}]
      }
    ])

    assert length(Alerts.evaluate()) == 1

    Application.delete_env(:monitorex, :alerts)
    :meck.unload(module)
  end
end
