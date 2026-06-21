defmodule Monitorex.Components.Live.AlertsPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  alias Monitorex.AlertHistory
  alias Monitorex.Alerts
  alias Monitorex.Components.Live.AlertsPage

  setup do
    if Process.whereis(AlertHistory) do
      :ets.delete_all_objects(:monitorex_alerts_history)
    else
      {:ok, _pid} = AlertHistory.start_link([])
    end

    if Process.whereis(Alerts) do
      Enum.each(Alerts.list_rules(), fn rule -> Alerts.remove_rule(rule.name) end)
    end

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

  test "renders alert center with no firing alerts" do
    html = render_component(AlertsPage, %{id: "alerts"})

    assert html =~ "Alert Center"
    assert html =~ "All clear"
    assert html =~ "No alert history yet"
  end

  test "renders firing alerts and history" do
    alert = sample_alert()
    AlertHistory.record_alert(alert)

    html = render_component(AlertsPage, %{id: "alerts"})

    assert html =~ "Firing Alerts"
    assert html =~ "High error rate"
    assert html =~ "api.example.com"
    assert html =~ "Acknowledge"
    assert html =~ "Snooze 15m"
    assert html =~ "Alert History"
  end

  test "renders firing alert consistently on re-render" do
    alert = sample_alert()
    AlertHistory.record_alert(alert)

    html =
      render_component(AlertsPage, %{id: "alerts"}) |> tap(fn _ ->
        assert AlertHistory.firing_count() == 1
      end)

    assert html =~ "High error rate"

    html = render_component(AlertsPage, %{id: "alerts"})

    assert html =~ "Alert Center"
  end

  test "renders firing alert with host details" do
    alert = sample_alert()
    AlertHistory.record_alert(alert)

    html = render_component(AlertsPage, %{id: "alerts"})
    assert html =~ "High error rate"
    assert html =~ "api.example.com"
  end

  test "renders rules count" do
    if Process.whereis(Alerts) do
      Alerts.add_rule(%{name: "Test Rule", metric: :error_rate, op: :gt, threshold: 0.1})

      html = render_component(AlertsPage, %{id: "alerts"})
      assert html =~ "Rules"

      Alerts.remove_rule("Test Rule")
    end
  end

  test "renders without crashing when Alerts GenServer is not started" do
    html = render_component(AlertsPage, %{id: "alerts"})
    assert html =~ "Alert Center"
    assert html =~ "All clear"
    assert html =~ "No alert history yet"
    assert html =~ "Rules"
  end

  describe "handle_event/3" do
    test "acknowledge event calls AlertHistory and refreshes" do
      alert = sample_alert()
      AlertHistory.record_alert(alert)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          firing_count: 1,
          firing: [alert],
          history: [alert],
          rules: [],
          page: 1,
          per_page: 20
        }
      }

      assert {:noreply, updated} =
               AlertsPage.handle_event("acknowledge", %{"id" => to_string(alert.id)}, socket)

      assert updated.assigns.firing_count == 0
    end

    test "snooze event calls AlertHistory and refreshes" do
      alert = sample_alert()
      AlertHistory.record_alert(alert)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          firing_count: 1,
          firing: [alert],
          history: [alert],
          rules: [],
          page: 1,
          per_page: 20
        }
      }

      assert {:noreply, updated} =
               AlertsPage.handle_event(
                 "snooze",
                 %{"id" => to_string(alert.id), "minutes" => "15"},
                 socket
               )

      assert updated.assigns.firing_count == 0
    end

    test "refresh event reloads alert state" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          firing_count: 0,
          firing: [],
          history: [],
          rules: [],
          page: 1,
          per_page: 20
        }
      }

      assert {:noreply, updated} = AlertsPage.handle_event("refresh", %{}, socket)
      assert is_map(updated.assigns)
    end
  end
end
