defmodule Monitorex.Components.Live.OutboundRecentPage do
  @moduledoc """
  LiveComponent that renders a live feed of recent outbound requests.

  Displays filter controls (status_class dropdown, host filter) and a table
  with color-coded status badges. Auto-refreshes via parent DashboardLive's
  refresh timer (sends `:refresh` every 2s), which triggers update/2 on
  the component, re-querying Storage.
  """
  use Phoenix.LiveComponent

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @impl true
  def update(assigns, socket) do
    host = assigns[:host]
    status_class = parse_status_class(assigns[:status_class])

    events = Storage.list_recent_outbound(
      host: host,
      status_class: status_class,
      limit: assigns[:limit] || 50
    )

    rows = Enum.map(events, &build_row/1)

    socket =
      socket
      |> assign(:events, events)
      |> assign(:rows, rows)
      |> assign(:filter_host, host || "")
      |> assign(:filter_status_class, assigns[:status_class] || "")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_status_class", %{"status_class" => value}, socket) do
    send(self(), {:navigate, "?page=outbound_recent&status_class=#{value}"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_host", %{"host" => value}, socket) do
    send(self(), {:navigate, "?page=outbound_recent&host=#{value}"})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="outbound-recent">
      <h2>Recent Outbound Requests</h2>

      <div class="filters">
        <label class="filter-label">
          Status:
          <select class="filter-select" phx-change="filter_status_class">
            <option value="">All</option>
            <option value="success" selected={@filter_status_class == "success"}>Success (2xx)</option>
            <option value="redirect" selected={@filter_status_class == "redirect"}>Redirect (3xx)</option>
            <option value="client_error" selected={@filter_status_class == "client_error"}>Client Error (4xx)</option>
            <option value="server_error" selected={@filter_status_class == "server_error"}>Server Error (5xx)</option>
          </select>
        </label>

        <label class="filter-label">
          Host:
          <input type="text" class="filter-input" name="host" value={@filter_host} phx-change="filter_host" placeholder="Filter by host..." />
        </label>
      </div>

      <div class="recent-table">
        <table class="data-table">
          <thead>
            <tr>
              <th class="data-table-th">Time</th>
              <th class="data-table-th">Method</th>
              <th class="data-table-th">URL</th>
              <th class="data-table-th">Status</th>
              <th class="data-table-th">Duration</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="data-table-row">
              <td class="data-table-td"><%= row.time %></td>
              <td class="data-table-td"><%= row.method %></td>
              <td class="data-table-td"><%= row.url %></td>
              <td class="data-table-td"><Core.status_badge status={row.status} /></td>
              <td class="data-table-td"><%= row.duration %></td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan="5" class="data-table-empty">No recent outbound requests</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp build_row(event) do
    %{
      time: format_timestamp(event.timestamp),
      method: event.method || "-",
      url: truncate_url(event.full_url || event.path || "-"),
      status: event.status || 0,
      duration: format_duration(event.duration_ms)
    }
  end

  defp format_timestamp(nil), do: "-"
  defp format_timestamp(ts) when is_integer(ts) do
    try do
      ts
      |> DateTime.from_unix(:microsecond)
      |> case do
        {:ok, dt} -> Calendar.strftime(dt, "%H:%M:%S")
        _ -> "-#{ts}-"
      end
    rescue
      _ -> "#{trunc(ts / 1_000_000)}s ago"
    end
  end
  defp format_timestamp(_), do: "-"

  defp truncate_url(url) when is_binary(url) do
    if String.length(url) > 60 do
      String.slice(url, 0, 57) <> "..."
    else
      url
    end
  end
  defp truncate_url(_), do: "-"

  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n, 2)}ms"
  defp format_duration(_), do: "-"

  defp parse_status_class(nil), do: nil
  defp parse_status_class(str) when is_binary(str) do
    case str do
      "success" -> :success
      "redirect" -> :redirect
      "client_error" -> :client_error
      "server_error" -> :server_error
      _ -> nil
    end
  end
  defp parse_status_class(atom) when is_atom(atom), do: atom
end
