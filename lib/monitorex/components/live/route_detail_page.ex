defmodule Monitorex.Components.Live.RouteDetailPage do
  @moduledoc """
  LiveComponent that shows detailed statistics for a specific inbound route.

  Receives a `:route` param in the format `"Method:/path"` and an optional
  `:page` param. Displays route summary (method, path, total requests,
  error rate), top consumers table, and a recent requests feed for this route.
  """
  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @impl true
  def update(assigns, socket) do
    route = assigns[:route]

    routes = Storage.list_routes()
    route_summary = Enum.find(routes, %{}, &("#{&1.method}:#{&1.path}" == route))

    consumers =
      try do
        Storage.list_consumers_for_route(route)
      rescue
        _ -> []
      end

    recent = Storage.list_recent_inbound(route: route, limit: 20)
    recent_rows = Enum.map(recent, &build_recent_row/1)

    [method, path] = split_route_key(route)

    socket =
      socket
      |> assign(:route_key, route)
      |> assign(:method, method)
      |> assign(:path, path)
      |> assign(:route_summary, route_summary)
      |> assign(:consumers, consumers)
      |> assign(:recent_rows, recent_rows)
      |> assign(:recent, recent)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="route-detail">
      <h2>Route: <%= @method %> <%= @path %></h2>

      <div class="summary-cards">
        <Core.summary_card label="Total Requests" value={format_number(@route_summary[:requests] || 0)} />
        <Core.summary_card label="Error Rate" value={format_percentage(@route_summary[:error_rate] || 0)} trend={if (@route_summary[:error_rate] || 0) > 0, do: :up, else: :down} />
        <Core.summary_card label="Avg Latency" value={format_duration(@route_summary[:avg_latency] || 0)} />
      </div>

      <h3>Top Consumers</h3>
      <div class="consumers-table">
        <table class="data-table">
          <thead>
            <tr>
              <th class="data-table-th">Consumer</th>
              <th class="data-table-th">Requests</th>
              <th class="data-table-th">Error Rate</th>
              <th class="data-table-th">Avg Latency</th>
              <th class="data-table-th">Last Seen</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={consumer <- @consumers} class="data-table-row">
              <td class="data-table-td"><%= consumer.consumer %></td>
              <td class="data-table-td"><%= format_number(consumer.requests) %></td>
              <td class="data-table-td"><%= format_percentage(error_rate(consumer)) %></td>
              <td class="data-table-td"><%= format_duration(consumer.avg_latency) %></td>
              <td class="data-table-td"><%= format_timestamp(consumer.last_seen) %></td>
            </tr>
            <tr :if={@consumers == []}>
              <td colspan="5" class="data-table-empty">No consumers found for this route</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h3>Recent Requests</h3>
      <div class="recent-table">
        <table class="data-table">
          <thead>
            <tr>
              <th class="data-table-th">Time</th>
              <th class="data-table-th">Consumer</th>
              <th class="data-table-th">Method</th>
              <th class="data-table-th">Status</th>
              <th class="data-table-th">Duration</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @recent_rows} class="data-table-row">
              <td class="data-table-td"><%= row.time %></td>
              <td class="data-table-td"><%= row.consumer %></td>
              <td class="data-table-td"><%= row.method %></td>
              <td class="data-table-td"><Core.status_badge status={row.status} /></td>
              <td class="data-table-td"><%= row.duration %></td>
            </tr>
            <tr :if={@recent_rows == []}>
              <td colspan="5" class="data-table-empty">No recent requests for this route</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp build_recent_row(event) do
    %{
      time: format_timestamp(event.timestamp),
      consumer: event.consumer || "-",
      method: event.method || "-",
      status: event.status || 0,
      duration: format_duration(event.duration_ms)
    }
  end

  defp error_rate(consumer) do
    requests = consumer.requests || 0
    errors = consumer.errors || 0
    if requests > 0, do: errors / requests * 100, else: 0.0
  end

  defp split_route_key(route_key) when is_binary(route_key) do
    case String.split(route_key, ":", parts: 2) do
      [method, path] -> [method, path]
      _ -> ["?", route_key]
    end
  end

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    Float.round(n / 1, 1) |> then(&"#{&1}%")
  end
  defp format_percentage(_), do: "0%"

  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n / 1, 2)}ms"
  defp format_duration(_), do: "-"
end
