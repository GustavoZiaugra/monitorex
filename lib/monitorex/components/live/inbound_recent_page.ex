defmodule Monitorex.Components.Live.InboundRecentPage do
  @moduledoc """
  LiveComponent that renders a live feed of recent inbound requests.

  Displays filter controls (status_class, consumer, route dropdowns) and
  a table with color-coded status badges. Supports optional filtering by
  `:status_class`, `:consumer`, and `:route` passed via assigns.

  Auto-refreshes via parent DashboardLive's refresh timer, which triggers
  update/2 on the component, re-querying Storage.
  """
  use Phoenix.LiveComponent

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @impl true
  def update(assigns, socket) do
    status_class = parse_status_class(assigns[:status_class])
    consumer = assigns[:consumer]
    route = assigns[:route]

    events = Storage.list_recent_inbound(
      status_class: status_class,
      consumer: consumer,
      route: route,
      limit: assigns[:limit] || 50
    )

    rows = Enum.map(events, &build_row/1)

    # Build dropdown options from existing data
    consumers = list_consumers()
    routes = list_routes()

    socket =
      socket
      |> assign(:events, events)
      |> assign(:rows, rows)
      |> assign(:filter_status_class, assigns[:status_class] || "")
      |> assign(:filter_consumer, consumer || "")
      |> assign(:filter_route, route || "")
      |> assign(:consumers, consumers)
      |> assign(:routes, routes)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_status_class", %{"status_class" => value}, socket) do
    base = base_filter_url(socket)
    send(self(), {:navigate, base <> "&status_class=#{value}"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_consumer", %{"consumer" => value}, socket) do
    base = base_filter_url(socket)
    send(self(), {:navigate, base <> "&consumer=#{value}"})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_route", %{"route" => value}, socket) do
    base = base_filter_url(socket)
    send(self(), {:navigate, base <> "&route=#{value}"})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inbound-recent">
      <h2>Recent Inbound Requests</h2>

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
          Consumer:
          <select class="filter-select" phx-change="filter_consumer">
            <option value="">All Consumers</option>
            <option :for={c <- @consumers} value={c} selected={c == @filter_consumer}><%= c %></option>
          </select>
        </label>

        <label class="filter-label">
          Route:
          <select class="filter-select" phx-change="filter_route">
            <option value="">All Routes</option>
            <option :for={r <- @routes} value={r} selected={r == @filter_route}><%= r %></option>
          </select>
        </label>
      </div>

      <div class="recent-table">
        <table class="data-table">
          <thead>
            <tr>
              <th class="data-table-th">Time</th>
              <th class="data-table-th">Consumer</th>
              <th class="data-table-th">Method</th>
              <th class="data-table-th">Route</th>
              <th class="data-table-th">Status</th>
              <th class="data-table-th">Duration</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="data-table-row">
              <td class="data-table-td"><%= row.time %></td>
              <td class="data-table-td"><%= row.consumer %></td>
              <td class="data-table-td"><%= row.method %></td>
              <td class="data-table-td"><%= row.route %></td>
              <td class="data-table-td"><Core.status_badge status={row.status} /></td>
              <td class="data-table-td"><%= row.duration %></td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan="6" class="data-table-empty">No recent inbound requests</td>
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
      consumer: event.consumer || "-",
      method: event.method || "-",
      route: "#{event.method || "?"}:#{event.path || "?"}",
      status: event.status || 0,
      duration: format_duration(event.duration_ms)
    }
  end

  defp list_consumers do
    try do
      Storage.list_consumers()
      |> Enum.map(& &1.consumer)
      |> Enum.sort()
    rescue
      _ -> []
    end
  end

  defp list_routes do
    try do
      Storage.list_routes()
      |> Enum.map(&"#{&1.method}:#{&1.path}")
      |> Enum.sort()
    rescue
      _ -> []
    end
  end

  defp base_filter_url(socket) do
    params = %{
      "page" => "inbound_recent",
      "status_class" => socket.assigns.filter_status_class,
      "consumer" => socket.assigns.filter_consumer,
      "route" => socket.assigns.filter_route
    }
    |> Enum.filter(fn {_k, v} -> v != "" end)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join("&")

    "?" <> params
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
