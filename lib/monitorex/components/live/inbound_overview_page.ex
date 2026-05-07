defmodule Monitorex.Components.Live.InboundOverviewPage do
  @moduledoc """
  LiveComponent that renders the inbound overview dashboard.

  Displays summary cards (Total Requests, Routes, Error Rate), a node
  selector for filtering, and a routes data table. Clicking a route row
  navigates to `/route/Method:/path`.
  """
  use Phoenix.LiveComponent

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @impl true
  def update(_assigns, socket) do
    routes = Storage.list_routes()

    total_requests = Enum.reduce(routes, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(routes, 0, &(&1.errors + &2))

    error_rate = if total_requests > 0, do: total_errors / total_requests * 100, else: 0.0

    route_rows = Enum.map(routes, &build_route_row/1)

    socket =
      socket
      |> assign(:routes, routes)
      |> assign(:route_rows, route_rows)
      |> assign(:total_requests, total_requests)
      |> assign(:route_count, length(routes))
      |> assign(:error_rate, error_rate)

    {:ok, socket}
  end

  @impl true
  def handle_event("navigate", %{"path" => path}, socket) do
    send(self(), {:navigate, path})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inbound-overview">
      <h2>Inbound Overview</h2>

      <div class="summary-cards">
        <Core.summary_card label="Total Requests" value={format_number(@total_requests)} />
        <Core.summary_card label="Routes" value={format_number(@route_count)} />
        <Core.summary_card label="Error Rate" value={format_percentage(@error_rate)} trend={if @error_rate > 0, do: :up, else: :down} />
      </div>

      <div class="routes-table">
        <table class="data-table">
          <thead>
            <tr>
              <th class="data-table-th">Method</th>
              <th class="data-table-th">Route</th>
              <th class="data-table-th">Requests</th>
              <th class="data-table-th">P95</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={route <- @route_rows} class="data-table-row" phx-click="navigate" phx-value-path={"/route/" <> route.method <> ":" <> route.path}>
              <td class="data-table-td"><%= route.method %></td>
              <td class="data-table-td"><%= route.path %></td>
              <td class="data-table-td"><%= route.requests %></td>
              <td class="data-table-td"><%= route.p95 %></td>
            </tr>
            <tr :if={@route_rows == []}>
              <td colspan="4" class="data-table-empty">No routes found</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp build_route_row(route) do
    %{
      method: route.method,
      path: route.path,
      requests: format_number(route.requests),
      p95: format_ms(route.p95)
    }
  end

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    Float.round(n, 1) |> then(&"#{&1}%")
  end
  defp format_percentage(_), do: "0%"

  defp format_ms(nil), do: "-"
  defp format_ms(n) when is_number(n), do: "#{Float.round(n, 1)}ms"
  defp format_ms(_), do: "-"
end
