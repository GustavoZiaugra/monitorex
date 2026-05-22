defmodule Monitorex.AlertHistoryTest do
  use ExUnit.Case, async: false

  alias Monitorex.AlertHistory

  setup do
    # Clean config env FIRST (before starting GenServer)
    Application.delete_env(:monitorex, :alerts)

    # Ensure a clean AlertHistory GenServer for each test
    if Process.whereis(AlertHistory) do
      try do
        GenServer.stop(AlertHistory)
      catch
        _, _ -> :ok
      end
    end

    {:ok, _pid} = AlertHistory.start_link([])

    :ok
  end

  defp sample_alert do
    %{
      alert_name: "High error rate",
      host: "api.example.com",
      value: 0.15,
      threshold: 0.05,
      operator: :gt,
      reason: "error rate too high",
      timestamp: System.system_time(:second),
      metric: :error_rate,
      status: :firing,
      acknowledged_at: nil,
      snoozed_until: nil,
      id: System.system_time(:microsecond)
    }
  end

  describe "record_alert/1 and list_history/0" do
    test "records an alert and lists it" do
      alert = sample_alert()
      assert :ok = AlertHistory.record_alert(alert)

      history = AlertHistory.list_history()
      assert length(history) == 1
      assert hd(history).alert_name == "High error rate"
      assert hd(history).host == "api.example.com"
    end

    test "filters by status" do
      alert = sample_alert()
      AlertHistory.record_alert(alert)

      assert length(AlertHistory.list_history(status: :firing)) == 1
      assert AlertHistory.list_history(status: :acknowledged) == []
    end

    test "respects limit" do
      for i <- 1..5 do
        alert = %{sample_alert() | id: System.system_time(:microsecond) + i}
        AlertHistory.record_alert(alert)
      end

      assert length(AlertHistory.list_history(limit: 3)) == 3
    end
  end

  describe "acknowledge/1" do
    test "acknowledges a firing alert" do
      alert = sample_alert()
      AlertHistory.record_alert(alert)

      assert :ok = AlertHistory.acknowledge(alert.id)
      assert AlertHistory.firing_count() == 0
      assert hd(AlertHistory.list_history(status: :acknowledged)).status == :acknowledged
    end

    test "returns :not_found for unknown id" do
      assert :not_found = AlertHistory.acknowledge(9_999_999_999)
    end
  end

  describe "snooze/2" do
    test "snoozes an alert" do
      alert = sample_alert()
      AlertHistory.record_alert(alert)

      assert :ok = AlertHistory.snooze(alert.id, 60)
      assert AlertHistory.firing_count() == 0
      assert hd(AlertHistory.list_history(status: :snoozed)).status == :snoozed
    end

    test "expire_snoozes restores firing status" do
      alert = sample_alert()
      AlertHistory.record_alert(alert)
      AlertHistory.snooze(alert.id, 1)

      # Should still be snoozed immediately
      assert AlertHistory.firing_count() == 0

      # Wait for snooze to expire
      Process.sleep(1100)
      AlertHistory.expire_snoozes()

      assert AlertHistory.firing_count() == 1
    end
  end

  describe "firing_count/0" do
    test "counts only firing alerts" do
      assert AlertHistory.firing_count() == 0

      a1 = sample_alert()
      a2 = %{sample_alert() | id: System.system_time(:microsecond) + 1}
      AlertHistory.record_alert(a1)
      AlertHistory.record_alert(a2)

      assert AlertHistory.firing_count() == 2

      AlertHistory.acknowledge(a1.id)
      assert AlertHistory.firing_count() == 1
    end
  end

  describe "trim/0" do
    test "removes oldest entries beyond max" do
      Application.put_env(:monitorex, :max_alert_history, 3)

      for i <- 1..5 do
        alert = %{sample_alert() | id: System.system_time(:microsecond) + i}
        AlertHistory.record_alert(alert)
      end

      AlertHistory.trim()
      assert length(AlertHistory.list_history()) == 3
    end
  end
end
