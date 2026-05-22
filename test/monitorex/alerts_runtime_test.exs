defmodule Monitorex.AlertsRuntimeTest do
  use ExUnit.Case, async: false

  alias Monitorex.Alerts

  setup do
    # Clean config env
    Application.delete_env(:monitorex, :alerts)

    # Reset Alerts state without stopping the GenServer (avoids supervisor restart issues)
    if Process.whereis(Alerts) do
      :sys.replace_state(Alerts, fn _state ->
        %{rules: [], debounce_table: create_debounce_table()}
      end)
    else
      {:ok, _pid} = Alerts.start_link([])
    end

    :ok
  end

  test "list_rules/0 returns empty when no config" do
    assert Alerts.list_rules() == []
  end

  test "add_rule/1 adds a runtime rule" do
    assert Alerts.list_rules() == []

    Alerts.add_rule(%{name: "Runtime rule", metric: :requests_per_min, op: :gt, threshold: 100})
    rules = Alerts.list_rules()
    assert length(rules) == 1
    assert hd(rules).name == "Runtime rule"
  end

  test "add_rule/1 replaces existing rule by name" do
    Alerts.add_rule(%{name: "Same", metric: :error_rate, op: :gt, threshold: 0.1})
    Alerts.add_rule(%{name: "Same", metric: :avg_latency_ms, op: :gt, threshold: 1000})

    rules = Alerts.list_rules()
    assert length(rules) == 1
    assert hd(rules).metric == :avg_latency_ms
  end

  test "remove_rule/1 removes by name" do
    Alerts.add_rule(%{name: "A", metric: :error_rate, op: :gt, threshold: 0.1})
    Alerts.add_rule(%{name: "B", metric: :error_rate, op: :gt, threshold: 0.1})

    assert :ok = Alerts.remove_rule("A")
    assert length(Alerts.list_rules()) == 1
    assert hd(Alerts.list_rules()).name == "B"
  end

  test "remove_rule/1 returns :not_found for unknown" do
    assert :not_found = Alerts.remove_rule("nonexistent")
  end

  defp create_debounce_table do
    table = :monitorex_alert_debounce

    case :ets.info(table) do
      :undefined ->
        :ets.new(table, [:public, :named_table, :set])

      _ ->
        :ets.delete_all_objects(table)
        table
    end
  end
end
