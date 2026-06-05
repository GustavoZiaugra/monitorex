defmodule Monitorex.Components.Live.InboundOverviewPage do
  @moduledoc """
  LiveComponent that renders the inbound overview dashboard.

  Displays summary cards (Total Requests, Routes, Error Rate), a node
  selector for filtering, and a routes data table. Clicking a route row
  navigates to `/route/Method:/path`.

  Supports sortable columns with state persisted in URL params.
  """
  use Phoenix.LiveComponent

  alias Monitorex.ClusterPage
  alias Monitorex.Components.Core

  @impl true
  def update(assigns, socket) do
    routes = ClusterPage.list_routes()

    total_requests = Enum.reduce(routes, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(routes, 0, &(&1.errors + &2))

    error_rate = if total_requests > 0, do: total_errors / total_requests * 100, else: 0.0

    sort_by = assigns[:sort_by] || "requests"
    sort_dir = assigns[:sort_dir] || "desc"

    sorted_routes = sort_routes(routes, sort_by, sort_dir)
    route_rows = Enum.map(sorted_routes, &build_route_row/1)
    table_columns = build_table_columns()

    socket =
      socket
      |> assign(:routes, sorted_routes)
      |> assign(:route_rows, route_rows)
      |> assign(:table_columns, table_columns)
      |> assign(:total_requests, total_requests)
      |> assign(:route_count, length(sorted_routes))
      |> assign(:error_rate, error_rate)
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)

    {:ok, socket}
  end

  @impl true
  def handle_event("navigate", %{"path" => path}, socket) do
    send(self(), {:navigate, path})
    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"key" => key}, socket) do
    %{sort_by: current_sort, sort_dir: current_dir} = socket.assigns

    new_dir =
      if key == current_sort and current_dir == "desc", do: "asc", else: "desc"

    base = "?page=inbound&sort_by=#{key}&sort_dir=#{new_dir}"
    send(self(), {:navigate, base})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inbound-overview">
    <Core.page_header title="Inbound Overview" subtitle="Monitor inbound HTTP requests">
        <Core.export_button page_name="inbound_overview" />
        </Core.page_header>

      <div class="summary-cards">
        <Core.summary_card label="Total Requests" value={format_number(@total_requests)} icon={~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>]} />
        <Core.summary_card label="Routes" value={format_number(@route_count)} icon={~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/></svg>]} />
        <Core.summary_card label="Error Rate" value={format_percentage(@error_rate)} trend={if @error_rate > 0, do: :up, else: :down} icon={~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>]} />
      </div>

      <div class="routes-table">
        <Core.data_table columns={@table_columns} rows={@route_rows} empty_message="No routes found" sort_by={@sort_by} sort_dir={@sort_dir} />
      </div>
    </div>
    """
  end

  defp build_table_columns do
    [
      %{label: "Method", key: :method, sortable?: true},
      %{label: "Route", key: :path, sortable?: true},
      %{label: "Requests", key: :requests, sortable?: true},
      %{label: "P95", key: :p95, sortable?: true}
    ]
  end

  defp build_route_row(route) do
    %{
      method: route.method,
      path: route.path,
      requests: format_number(route.requests),
      p95: format_ms(route.p95)
    }
  end

  defp sort_routes(routes, sort_by, sort_dir) do
    sorted =
      case sort_by do
        "method" -> Enum.sort_by(routes, & &1.method)
        "path" -> Enum.sort_by(routes, & &1.path)
        "requests" -> Enum.sort_by(routes, & &1.requests)
        "p95" -> Enum.sort_by(routes, &(&1.p95 || 0))
        _ -> Enum.sort_by(routes, & &1.requests)
      end

    if sort_dir == "desc", do: Enum.reverse(sorted), else: sorted
  end

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    "#{Float.round(n / 1, 1)}%"
  end

  defp format_percentage(_), do: "0%"

  defp format_ms(nil), do: "-"
  defp format_ms(n) when is_number(n), do: "#{Float.round(n, 1)}ms"
  defp format_ms(_), do: "-"
end
