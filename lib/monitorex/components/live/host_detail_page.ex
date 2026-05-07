defmodule Monitorex.Components.Live.HostDetailPage do
  @moduledoc """
  LiveComponent that shows detailed statistics for a specific outbound host.

  Receives a `:host` param identifying the host and an optional `:page` param.
  Displays summary cards (Total Requests, Endpoints, Avg Latency, Error Rate),
  a per-endpoint breakdown table, and a recent requests feed (limited to 20).
  """
  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @sortable_fields ~w(path requests avg_latency error_rate)

  @impl true
  def update(assigns, socket) do
    host = assigns[:host]

    endpoints = Storage.list_endpoints_for_host(host)
    recent = Storage.list_recent_outbound(host: host, limit: 20)

    sort_by = assigns[:sort_by] || "requests"
    sort_dir = assigns[:sort_dir] || "desc"

    total_requests = Enum.reduce(endpoints, 0, &(&1.requests + &2))
    total_errors = Enum.reduce(endpoints, 0, &(&1.errors + &2))
    total_duration = Enum.reduce(endpoints, 0, &(&1.total_duration + &2))

    error_rate = if total_requests > 0, do: total_errors / total_requests * 100, else: 0.0
    avg_latency = if total_requests > 0, do: total_duration / total_requests, else: 0.0

    sorted_endpoints = sort_endpoints(endpoints, sort_by, sort_dir)
    endpoint_rows = Enum.map(sorted_endpoints, &build_endpoint_row/1)
    recent_rows = Enum.map(recent, &build_recent_row/1)

    socket =
      socket
      |> assign(:host, host)
      |> assign(:endpoints, endpoints)
      |> assign(:endpoint_rows, endpoint_rows)
      |> assign(:total_requests, total_requests)
      |> assign(:total_errors, total_errors)
      |> assign(:error_rate, error_rate)
      |> assign(:avg_latency, avg_latency)
      |> assign(:endpoint_count, length(endpoints))
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

    base = "?page=host&host=#{URI.encode(socket.assigns.host)}"
    send(self(), {:navigate, base <> "&sort_by=#{key}&sort_dir=#{new_dir}"})

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="host-detail">
      <h2>Host: <%= @host %></h2>

      <div class="summary-cards">
        <Core.summary_card label="Total Requests" value={format_number(@total_requests)} />
        <Core.summary_card label="Endpoints" value={format_number(@endpoint_count)} />
        <Core.summary_card label="Avg Latency" value={format_duration(@avg_latency)} />
        <Core.summary_card label="Error Rate" value={format_percentage(@error_rate)} trend={if @error_rate > 0, do: :up, else: :down} />
      </div>

      <h3>Endpoints</h3>
      <div class="endpoints-table">
        <Core.data_table columns={[
          %{label: "Path", key: :path, sortable?: true},
          %{label: "Requests", key: :requests, sortable?: true},
          %{label: "Avg", key: :avg_latency, sortable?: true},
          %{label: "Error Rate", key: :error_rate, sortable?: true}
        ]}
        rows={@endpoint_rows}
        empty_message="No endpoints found"
        sort_by={@sort_by}
        sort_dir={@sort_dir} />
      </div>

      <h3>Recent Requests</h3>
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
            <tr :for={row <- @recent_rows} class="data-table-row">
              <td class="data-table-td"><%= row.time %></td>
              <td class="data-table-td"><%= row.method %></td>
              <td class="data-table-td"><%= row.url %></td>
              <td class="data-table-td"><Core.status_badge status={row.status} /></td>
              <td class="data-table-td"><%= row.duration %></td>
            </tr>
            <tr :if={@recent_rows == []}>
              <td colspan="5" class="data-table-empty">No recent requests for this host</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp build_endpoint_row(ep) do
    requests = ep.requests || 0
    errors = ep.errors || 0
    error_rate = if requests > 0, do: errors / requests * 100, else: 0.0

    %{
      path: ep.path,
      requests: format_number(requests),
      avg_latency: format_duration(ep.avg_latency),
      error_rate: format_percentage(error_rate)
    }
  end

  defp build_recent_row(event) do
    %{
      time: format_timestamp(event.timestamp),
      method: event.method || "-",
      url: event.full_url || event.path || "-",
      status: event.status || 0,
      duration: format_duration(event.duration_ms)
    }
  end

  defp sort_endpoints(endpoints, sort_by, sort_dir) do
    sorted =
      case sort_by do
        "path" -> Enum.sort_by(endpoints, & &1.path)
        "requests" -> Enum.sort_by(endpoints, & &1.requests)
        "avg_latency" -> Enum.sort_by(endpoints, &(&1.avg_latency || 0))
        "error_rate" ->
          Enum.sort_by(endpoints, fn ep ->
            req = ep.requests || 0
            err = ep.errors || 0
            if req > 0, do: err / req, else: 0.0
          end)
        _ -> Enum.sort_by(endpoints, & &1.requests)
      end

    if sort_dir == "desc", do: Enum.reverse(sorted), else: sorted
  end

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    Float.round(n, 1) |> then(&"#{&1}%")
  end
  defp format_percentage(_), do: "0%"

  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n, 2)}ms"
  defp format_duration(_), do: "-"
end
