defmodule Monitorex.Components.Live.RouteDetailPage do
  @moduledoc """
  LiveComponent that shows detailed statistics for a specific inbound route.

  Receives a `:route` param in the format `"Method:/path"` and an optional
  `:page` param. Displays route summary (method, path, total requests,
  error rate), top consumers table, and a recent requests feed for this route.
  """
  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.ClusterPage
  alias Monitorex.Components.Core

  @sortable_fields ~w(consumer requests error_rate avg_latency)

  @impl true
  def update(assigns, socket) do
    route = assigns[:route]

    routes = ClusterPage.list_routes()
    route_summary = Enum.find(routes, %{}, &("#{&1.method}:#{&1.path}" == route))

    consumers =
      try do
        ClusterPage.list_consumers_for_route(route)
      rescue
        _ -> []
      end

    recent = ClusterPage.list_recent_inbound(route: route, limit: 20)
    recent_rows = Enum.map(recent, &build_recent_row/1)

    sort_by = assigns[:sort_by] || "requests"
    sort_dir = assigns[:sort_dir] || "desc"
    sorted_consumers = sort_consumers(consumers, sort_by, sort_dir)
    consumer_rows = Enum.map(sorted_consumers, &build_consumer_row/1)

    [method, path] = split_route_key(route)

    socket =
      socket
      |> assign(:route_key, route)
      |> assign(:method, method)
      |> assign(:path, path)
      |> assign(:route_summary, route_summary)
      |> assign(:consumers, sorted_consumers)
      |> assign(:consumer_rows, consumer_rows)
      |> assign(:recent_rows, recent_rows)
      |> assign(:recent, recent)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)

    {:ok, socket}
  end

  @impl true
  def handle_event("sort", %{"key" => key}, socket) when key in @sortable_fields do
    %{sort_by: current_sort, sort_dir: current_dir} = socket.assigns

    new_dir = if key == current_sort and current_dir == "asc", do: "desc", else: "asc"

    base = "?page=route&host=#{URI.encode(socket.assigns.route_key)}"
    send(self(), {:navigate, base <> "&sort_by=#{key}&sort_dir=#{new_dir}"})

    {:noreply, socket}
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
        <Core.data_table columns={[
          %{label: "Consumer", key: :consumer, sortable?: true},
          %{label: "Requests", key: :requests, sortable?: true},
          %{label: "Error Rate", key: :error_rate, sortable?: true},
          %{label: "Avg Latency", key: :avg_latency, sortable?: true},
          %{label: "Last Seen", key: :last_seen}
        ]}
        rows={@consumer_rows}
        empty_message="No consumers found"
        sort_by={@sort_by}
        sort_dir={@sort_dir} />
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

  defp build_consumer_row(c) do
    %{
      consumer: c.consumer,
      requests: format_number(c.requests || 0),
      error_rate: format_percentage(error_rate(c)),
      avg_latency: format_duration(c.avg_latency),
      last_seen: format_timestamp(c.last_seen)
    }
  end

  defp error_rate(consumer) do
    req = consumer.requests || 0
    err = consumer.errors || 0
    if req > 0, do: err / req * 100, else: 0.0
  end

  defp sort_consumers(consumers, sort_by, sort_dir) do
    sorted =
      case sort_by do
        "consumer" -> Enum.sort_by(consumers, &(&1.consumer || ""))
        "requests" -> Enum.sort_by(consumers, &(&1.requests || 0))
        "avg_latency" -> Enum.sort_by(consumers, &(&1.avg_latency || 0))
        "error_rate" ->
          Enum.sort_by(consumers, fn c ->
            req = c.requests || 0
            err = c.errors || 0
            if req > 0, do: err / req, else: 0.0
          end)
        _ -> Enum.sort_by(consumers, &(&1.requests || 0))
      end

    if sort_dir == "desc", do: Enum.reverse(sorted), else: sorted
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
