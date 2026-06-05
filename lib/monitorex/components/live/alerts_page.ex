defmodule Monitorex.Components.Live.AlertsPage do
  @moduledoc """
  LiveComponent that renders the Alert Center dashboard page.

  Displays currently firing alerts, alert history, and provides
  acknowledge and snooze actions.
  """

  use Phoenix.LiveComponent

  alias Monitorex.AlertHistory
  alias Monitorex.Alerts
  alias Monitorex.Components.Core

  @impl true
  def update(_assigns, socket) do
    firing_count = AlertHistory.firing_count()
    firing = AlertHistory.list_history(status: :firing, limit: 50)
    history = AlertHistory.list_history(limit: 100)
    rules = Alerts.list_rules()

    socket =
      socket
      |> assign(:firing_count, firing_count)
      |> assign(:firing, firing)
      |> assign(:history, history)
      |> assign(:rules, rules)
      |> assign(:page, 1)
      |> assign(:per_page, 20)

    {:ok, socket}
  end

  @impl true
  def handle_event("acknowledge", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    AlertHistory.acknowledge(id)
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("snooze", %{"id" => id_str, "minutes" => minutes_str}, socket) do
    id = String.to_integer(id_str)
    minutes = String.to_integer(minutes_str)
    AlertHistory.snooze(id, minutes * 60)
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, refresh(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="alerts-page">
      <Core.page_header title="Alert Center" subtitle="Monitor and manage threshold-based alerts">
        <button class="export-btn" phx-click="refresh" phx-target={@myself}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="23 4 23 10 17 10"/>
            <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
          </svg>
          Refresh
        </button>
      </Core.page_header>

      <div class="summary-cards">
        <Core.summary_card label="Firing" value={to_string(@firing_count)} icon={alert_icon()} class={if @firing_count > 0, do: "alert-firing", else: ""} />
        <Core.summary_card label="History" value={to_string(length(@history))} icon={history_icon()} />
        <Core.summary_card label="Rules" value={to_string(length(@rules))} icon={rules_icon()} />
      </div>

      <h3 class="section-title">Firing Alerts</h3>
      <div class="alerts-firing">
        <%= if @firing == [] do %>
          <div class="alerts-empty">All clear — no firing alerts.</div>
        <% else %>
          <div :for={alert <- @firing} class={["alert-card", "alert-card-firing"]}>
            <div class="alert-card-header">
              <span class="alert-name"><%= alert.alert_name %></span>
              <span class="alert-host"><%= alert.host %></span>
              <span class="alert-metric"><%= alert.metric %></span>
            </div>
            <div class="alert-card-body">
              <div class="alert-value">
                <%= format_value(alert.value) %> / <%= format_value(alert.threshold) %>
              </div>
              <div class="alert-reason"><%= alert.reason %></div>
              <div class="alert-time"><%= format_time(alert.timestamp) %></div>
            </div>
            <div class="alert-card-actions">
              <button class="btn-ack" phx-click="acknowledge" phx-value-id={alert.id} phx-target={@myself}>Acknowledge</button>
              <button class="btn-snooze" phx-click="snooze" phx-value-id={alert.id} phx-value-minutes="15" phx-target={@myself}>Snooze 15m</button>
              <button class="btn-snooze" phx-click="snooze" phx-value-id={alert.id} phx-value-minutes="60" phx-target={@myself}>Snooze 1h</button>
            </div>
          </div>
        <% end %>
      </div>

      <h3 class="section-title">Alert History</h3>
      <div class="alerts-history">
        <%= if @history == [] do %>
          <div class="alerts-empty">No alert history yet.</div>
        <% else %>
          <Core.data_table
            columns={history_columns()}
            rows={history_rows(@history)}
            empty_message="No alert history"
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp refresh(socket) do
    firing_count = AlertHistory.firing_count()
    firing = AlertHistory.list_history(status: :firing, limit: 50)
    history = AlertHistory.list_history(limit: 100)
    rules = Alerts.list_rules()

    socket
    |> assign(:firing_count, firing_count)
    |> assign(:firing, firing)
    |> assign(:history, history)
    |> assign(:rules, rules)
  end

  defp alert_icon do
    ~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>]
  end

  defp history_icon do
    ~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>]
  end

  defp rules_icon do
    ~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg>]
  end

  defp history_columns do
    [
      %{label: "Alert", key: :alert_name, sortable?: false},
      %{label: "Host", key: :host, sortable?: false},
      %{label: "Metric", key: :metric, sortable?: false},
      %{label: "Value", key: :value, sortable?: false},
      %{label: "Threshold", key: :threshold, sortable?: false},
      %{label: "Status", key: :status, sortable?: false},
      %{label: "Time", key: :time, sortable?: false}
    ]
  end

  defp history_rows(history) do
    Enum.map(history, fn alert ->
      %{
        alert_name: alert.alert_name,
        host: alert.host,
        metric: to_string(alert.metric),
        value: format_value(alert.value),
        threshold: format_value(alert.threshold),
        status: status_badge_text(alert.status),
        time: format_time(alert.timestamp)
      }
    end)
  end

  defp status_badge_text(:firing), do: "Firing"
  defp status_badge_text(:acknowledged), do: "Ack"
  defp status_badge_text(:snoozed), do: "Snoozed"
  defp status_badge_text(_), do: "Unknown"

  defp format_value(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_value(v), do: to_string(v)

  defp format_time(ts) when is_integer(ts) do
    Calendar.strftime(DateTime.from_unix!(ts), "%Y-%m-%d %H:%M:%S")
  end

  defp format_time(_), do: "-"
end
