defmodule Monitorex.Components.Live.InboundRecentPage do
  @moduledoc """
  LiveComponent that renders a live feed of recent inbound requests.

  Displays filter controls (status_class chips, consumer dropdown, route dropdown)
  and a table with color-coded status badges, with pagination.

  Supports optional filtering by `:status_class`, `:consumer`, and `:route`
  passed via assigns. Auto-refreshes via parent DashboardLive's refresh timer,
  which triggers update/2 on the component, re-querying Storage.

  Sort/filter/page state persisted in URL query params.
  """
  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @page_size 50

  @impl true
  def update(assigns, socket) do
    status_class = parse_status_class(assigns[:status_class])
    consumer = assigns[:consumer]
    route = assigns[:route]
    page = max(1, assigns[:page] || 1)
    page_size = assigns[:page_size] || @page_size
    offset = (page - 1) * page_size

    events = Storage.list_recent_inbound(
      status_class: status_class,
      consumer: consumer,
      route: route,
      limit: page_size,
      offset: offset
    )

    total_count = Storage.count_recent_inbound(
      status_class: status_class,
      consumer: consumer,
      route: route
    )

    rows = Enum.map(events, &build_row/1)
    total_pages = max(1, ceil(total_count / page_size))

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
      |> assign(:page, page)
      |> assign(:page_size, page_size)
      |> assign(:total_count, total_count)
      |> assign(:total_pages, total_pages)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_status_class", %{"status_class" => value}, socket) do
    base = base_filter_url(socket, value)
    send(self(), {:navigate, base})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_consumer", %{"consumer" => value}, socket) do
    base = base_filter_url(socket, nil)
    parts = if value != "", do: "&consumer=#{URI.encode(value)}", else: ""
    send(self(), {:navigate, base <> parts})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_route", %{"route" => value}, socket) do
    base = base_filter_url(socket, nil)
    parts = if value != "", do: "&route=#{URI.encode(value)}", else: ""
    send(self(), {:navigate, base <> parts})
    {:noreply, socket}
  end

  @impl true
  def handle_event("go_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    base = base_filter_url(socket, nil)
    send(self(), {:navigate, base <> "&page=#{page}"})
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
          <span class={status_chip_class("2xx", @filter_status_class)} phx-click="filter_status_class" phx-value-status_class="2xx">2xx</span>
          <span class={status_chip_class("3xx", @filter_status_class)} phx-click="filter_status_class" phx-value-status_class="3xx">3xx</span>
          <span class={status_chip_class("4xx", @filter_status_class)} phx-click="filter_status_class" phx-value-status_class="4xx">4xx</span>
          <span class={status_chip_class("5xx", @filter_status_class)} phx-click="filter_status_class" phx-value-status_class="5xx">5xx</span>
          <span :if={@filter_status_class != ""} class="filter-chip" phx-click="filter_status_class" phx-value-status_class="">Clear</span>
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
        <div class="data-table-container">
          <table class="data-table">
            <thead>
              <tr>
                <th class="data-table-th">Time</th>
                <th class="data-table-th">Consumer</th>
                <th class="data-table-th">Method</th>
                <th class="data-table-th">Route</th>
                <th class="data-table-th">Status</th>
                <th class="data-table-th hide-mobile">Duration</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} class="data-table-row">
                <td class="data-table-td" data-label="Time"><%= row.time %></td>
                <td class="data-table-td" data-label="Consumer"><%= row.consumer %></td>
                <td class="data-table-td" data-label="Method"><%= row.method %></td>
                <td class="data-table-td" data-label="Route"><%= row.route %></td>
                <td class="data-table-td" data-label="Status"><Core.status_badge status={row.status} /></td>
                <td class="data-table-td hide-mobile" data-label="Duration"><%= row.duration %></td>
              </tr>
              <tr :if={@rows == []}>
                <td colspan="6" class="data-table-empty">No recent inbound requests</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <.pagination current={@page} total={@total_pages} />
    </div>
    """
  end

  defp pagination(assigns) do
    ~H"""
    <div class="pagination">
      <button class="page-btn" phx-click="go_page" phx-value-page={@current - 1} disabled={@current <= 1}>
        &laquo; Prev
      </button>
      <span :for={p <- visible_pages(@current, @total)} class={["page-btn", if(p == @current, do: "active")]} phx-click="go_page" phx-value-page={p}>
        <%= if p == :ellipsis, do: "...", else: p %>
      </span>
      <button class="page-btn" phx-click="go_page" phx-value-page={@current + 1} disabled={@current >= @total}>
        Next &raquo;
      </button>
      <span class="page-info"><%= @current %> / <%= @total %></span>
    </div>
    """
  end

  defp visible_pages(current, total) do
    cond do
      total <= 7 -> Enum.to_list(1..total)
      current <= 4 -> [1, 2, 3, 4, 5, :ellipsis, total]
      current >= total - 3 -> [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]
      true -> [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end

  defp base_filter_url(socket, status_class_override) do
    sc = if status_class_override != nil, do: status_class_override, else: socket.assigns.filter_status_class
    consumer = socket.assigns.filter_consumer
    route = socket.assigns.filter_route

    params = %{"page" => "inbound_recent"}
    |> then(fn p -> if sc != "", do: Map.put(p, "status_class", sc), else: p end)
    |> then(fn p -> if consumer != "", do: Map.put(p, "consumer", consumer), else: p end)
    |> then(fn p -> if route != "", do: Map.put(p, "route", route), else: p end)
    |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode(v)}" end)
    |> Enum.join("&")

    "?" <> params
  end

  defp status_chip_class(value, current) do
    base = "filter-chip"
    if value == current do
      case value do
        "2xx" -> "#{base} active-2xx"
        "3xx" -> "#{base} active-3xx"
        "4xx" -> "#{base} active-4xx"
        "5xx" -> "#{base} active-5xx"
        _ -> "#{base} active"
      end
    else
      base
    end
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


  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n, 2)}ms"
  defp format_duration(_), do: "-"

  defp parse_status_class(nil), do: nil
  defp parse_status_class(str) when is_binary(str) do
    case str do
      "2xx" -> :success
      "3xx" -> :redirect
      "4xx" -> :client_error
      "5xx" -> :server_error
      _ -> nil
    end
  end
  defp parse_status_class(atom) when is_atom(atom), do: atom
end
