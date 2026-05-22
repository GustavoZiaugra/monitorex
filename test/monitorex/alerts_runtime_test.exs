defmodule Monitorex.AlertsRuntimeTest do
  use ExUnit.Case, async: false

  alias Monitorex.Alerts

  setup do
    # Clean config env BEFORE starting GenServer
    Application.delete_env(:monitorex, :alerts)

    # Ensure a clean Alerts GenServer for each test
    if Process.whereis(Alerts) do
      try do
        GenServer.stop(Alerts)
      catch
        _, _ -> :ok
      end

      # Wait for process to terminate (supervisor may restart it)
      Process.sleep(50)
    end

    # If supervisor restarted it, it will have empty rules (config deleted above).
    # If not running at all, start it manually.
    unless Process.whereis(Alerts) do
      {:ok, _pid} = Alerts.start_link([])
    end

    :ok
  end

  test "loads config rules on init" do
    # Clean stop first and wait for termination
    try do
      GenServer.stop(Alerts)
    catch
      _, _ -> :ok
    end

    # Ensure process is fully dead before restarting
    Process.sleep(50)

    Application.put_env(:monitorex, :alerts, [
      %{name: "Config rule", metric: :error_rate, op: :gt, threshold: 0.1}
    ])

    # Re-start to pick up config
    {:ok, _pid} = Alerts.start_link([])

    rules = Alerts.list_rules()
    assert length(rules) == 1
    assert hd(rules).name == "Config rule"
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
end
