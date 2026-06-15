defmodule Monitorex.Components.Live.OutboundRecentPage do
  @moduledoc """
  LiveComponent that renders a live feed of recent outbound requests.

  Displays filter controls (status_class chips, host filter) and a table
  with color-coded status badges, with pagination. Auto-refreshes via
  parent DashboardLive's refresh timer (sends `:refresh` every 2s), which
  triggers update/2 on the component, re-querying ClusterPage.

  Sort/filter/page state persisted in URL query params.
  """
  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1, status_chip_class: 2]

  alias Monitorex.ClusterPage
  alias Monitorex.Components.Core

  @page_size 50

  @impl true
  def update(assigns, socket) do
    host = assigns[:host]
    status_class = parse_status_class(assigns[:status_class])
    page = max(1, assigns[:page] || 1)
    page_size = assigns[:page_size] || @page_size
    offset = (page - 1) * page_size

    events =
      ClusterPage.list_recent_outbound(
        host: host,
        status_class: status_class,
        limit: page_size,
        offset: offset
      )

    total_count =
      ClusterPage.count_recent_outbound(
        host: host,
        status_class: status_class
      )

    rows = Enum.map(events, &build_row/1)
    total_pages = max(1, ceil(total_count / page_size))

    show_node_column? = ClusterPage.cluster_enabled?()

    socket =
      socket
      |> assign(:events, events)
      |> assign(:rows, rows)
      |> assign(:show_node_column, show_node_column?)
      |> assign(:filter_host, host || "")
      |> assign(:filter_status_class, assigns[:status_class] || "")
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
  def handle_event("filter_host", %{"host" => value}, socket) do
    base = base_filter_url(socket, nil)
    parts = if value != "", do: "&host=#{value}", else: ""
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
    <div class="outbound-recent">
    <Core.page_header title="Recent Outbound Requests" subtitle="Live feed of outgoing HTTP requests">
        <Core.export_button page_name="outbound_recent" />
        </Core.page_header>

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
          Host:
          <input type="text" class="filter-input" name="host" value={@filter_host} phx-change="filter_host" phx-debounce="300" placeholder="Filter by host..." />
        </label>
      </div>

      <div class="recent-table">
        <div class="data-table-container">
          <table class="data-table">
            <thead>
              <tr>
                <th class="data-table-th">Time</th>
                <th class="data-table-th">Method</th>
                <th class="data-table-th">URL</th>
                <th class="data-table-th">Status</th>
                <th class="data-table-th hide-mobile">Duration</th>
                <th :if={@show_node_column} class="data-table-th hide-mobile">Node</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} class="data-table-row">
                <td class="data-table-td" data-label="Time"><%= row.time %></td>
                <td class="data-table-td" data-label="Method"><%= row.method %></td>
                <td class="data-table-td" data-label="URL"><%= row.url %></td>
                <td class="data-table-td" data-label="Status"><Core.status_badge status={row.status} /></td>
                <td class="data-table-td hide-mobile" data-label="Duration"><%= row.duration %></td>
                <td :if={@show_node_column} class="data-table-td hide-mobile" data-label="Node"><%= row[:node] || "-" %></td>
              </tr>
              <tr :if={@rows == []}>
                <td colspan={if @show_node_column, do: 6, else: 5} class="data-table-empty">No recent outbound requests</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <Core.pagination current={@page} total={@total_pages} event="go_page" />
    </div>
    """
  end

  defp base_filter_url(socket, status_class_override) do
    sc =
      if status_class_override != nil,
        do: status_class_override,
        else: socket.assigns.filter_status_class

    host = socket.assigns.filter_host

    params =
      %{
        "page" => "outbound_recent"
      }
      |> then(fn p -> if sc != "", do: Map.put(p, "status_class", sc), else: p end)
      |> then(fn p -> if host != "", do: Map.put(p, "host", host), else: p end)

    query = Enum.map_join(params, "&", fn {k, v} -> "#{k}=#{URI.encode(v)}" end)

    "?" <> query
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
      "2xx" -> :success
      "3xx" -> :redirect
      "4xx" -> :client_error
      "5xx" -> :server_error
      _ -> nil
    end
  end

  defp parse_status_class(atom) when is_atom(atom), do: atom
end
