defmodule Monitorex.Components.Live.OutboundOverviewPage do
  @moduledoc """
  LiveComponent that renders the outbound overview dashboard.

  Displays summary cards (total requests, error rate, avg latency),
  a node selector, and a host table with per-host statistics.
  Clicking a host navigates to the host detail page.
  """
  use Phoenix.LiveComponent

  alias Monitorex.ClusterPage
  alias Monitorex.Components.Core

  @impl true
  def update(assigns, socket) do
    hosts = ClusterPage.list_hosts()

    total_requests = Enum.reduce(hosts, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(hosts, 0, &(&1.errors + &2))
    total_duration = Enum.reduce(hosts, 0, &(&1.total_duration + &2))

    error_rate = if total_requests > 0, do: total_errors / total_requests * 100, else: 0.0
    avg_latency = if total_requests > 0, do: total_duration / total_requests, else: 0.0

    nodes = Enum.map(hosts, & &1.host)
    selected_node = assigns[:node] || ""

    sort_by = assigns[:sort_by] || "requests"
    sort_dir = assigns[:sort_dir] || "desc"

    sorted_hosts = sort_hosts(hosts, sort_by, sort_dir)
    table_columns = build_table_columns()
    table_rows = build_table_rows(sorted_hosts)

    socket =
      socket
      |> assign(:hosts, sorted_hosts)
      |> assign(:table_columns, table_columns)
      |> assign(:table_rows, table_rows)
      |> assign(:total_requests, total_requests)
      |> assign(:error_rate, error_rate)
      |> assign(:avg_latency, avg_latency)
      |> assign(:nodes, nodes)
      |> assign(:selected_node, selected_node)
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

    base = "?page=outbound&sort_by=#{key}&sort_dir=#{new_dir}"
    send(self(), {:navigate, base})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="outbound-overview">
      <Core.page_header title="Outbound Overview" subtitle="Monitor outbound HTTP requests by host">
        <Core.node_selector nodes={@nodes} selected={@selected_node} event="select_node" />
        <Core.export_button page_name="outbound_overview" />
      </Core.page_header>

      <div class="summary-cards">
        <Core.summary_card label="Total Requests" value={format_number(@total_requests)} icon={~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>]} />
        <Core.summary_card label="Error Rate" value={format_percentage(@error_rate)} trend={if @error_rate > 0, do: :up, else: :down} icon={~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>]} />
        <Core.summary_card label="Avg Latency" value={format_duration(@avg_latency)} icon={~S[<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>]} />
      </div>

      <div class="hosts-table">
        <Core.data_table columns={@table_columns} rows={@table_rows} empty_message="No hosts found" sort_by={@sort_by} sort_dir={@sort_dir} />
      </div>
    </div>
    """
  end

  defp build_table_columns do
    [
      %{label: "Host", key: :host, sortable?: true},
      %{label: "Client", key: :client, sortable?: true},
      %{label: "Requests", key: :requests, sortable?: true},
      %{label: "Avg", key: :avg_latency, sortable?: true},
      %{label: "P95", key: :p95, sortable?: true},
      %{label: "Error Rate", key: :error_rate, sortable?: true}
    ]
  end

  defp build_table_rows(hosts) do
    Enum.map(hosts, fn host ->
      %{
        host: host.host,
        client: host.client || "-",
        requests: format_number(host.requests),
        avg_latency: format_duration(host.avg_latency),
        p95: format_ms(host.p95),
        error_rate: format_percentage(host.error_rate)
      }
    end)
  end

  defp sort_hosts(hosts, sort_by, sort_dir) do
    sorted =
      case sort_by do
        "host" -> Enum.sort_by(hosts, & &1.host)
        "client" -> Enum.sort_by(hosts, &(&1.client || ""))
        "requests" -> Enum.sort_by(hosts, & &1.requests)
        "avg_latency" -> Enum.sort_by(hosts, & &1.avg_latency)
        "p95" -> Enum.sort_by(hosts, &(&1.p95 || 0))
        "error_rate" -> Enum.sort_by(hosts, & &1.error_rate)
        _ -> Enum.sort_by(hosts, & &1.requests)
      end

    if sort_dir == "desc", do: Enum.reverse(sorted), else: sorted
  end

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    Float.round(n, 1) |> then(&"#{&1}%")
  end

  defp format_percentage(_), do: "0%"

  defp format_duration(n) when is_number(n) do
    Float.round(n, 2) |> then(&"#{&1}ms")
  end

  defp format_duration(_), do: "0ms"

  defp format_ms(nil), do: "-"
  defp format_ms(n) when is_number(n), do: "#{Float.round(n, 1)}ms"
  defp format_ms(_), do: "-"
end
