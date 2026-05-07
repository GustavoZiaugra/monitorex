defmodule Monitorex.Components.Live.InboundConsumersPage do
  @moduledoc """
  LiveComponent that renders the inbound consumers dashboard.

  Displays a summary card with total consumer count and a data table
  with per-consumer statistics (requests, error rate, average latency).
  Supports sortable columns with state persisted in URL params.
  """
  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @impl true
  def update(assigns, socket) do
    consumers = Storage.list_consumers()

    sort_by = assigns[:sort_by] || "requests"
    sort_dir = assigns[:sort_dir] || "desc"

    sorted_consumers = sort_consumers(consumers, sort_by, sort_dir)
    consumer_rows = Enum.map(sorted_consumers, &build_consumer_row/1)
    table_columns = build_table_columns()

    socket =
      socket
      |> assign(:consumers, sorted_consumers)
      |> assign(:consumer_rows, consumer_rows)
      |> assign(:table_columns, table_columns)
      |> assign(:consumer_count, length(sorted_consumers))
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)

    {:ok, socket}
  end

  @impl true
  def handle_event("sort", %{"key" => key}, socket) do
    %{sort_by: current_sort, sort_dir: current_dir} = socket.assigns

    new_dir =
      if key == current_sort and current_dir == "desc", do: "asc", else: "desc"

    base = "?page=inbound_consumers&sort_by=#{key}&sort_dir=#{new_dir}"
    send(self(), {:navigate, base})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inbound-consumers">
      <h2>Inbound Consumers</h2>

      <div class="summary-cards">
        <Core.summary_card label="Total Consumers" value={format_number(@consumer_count)} />
      </div>

      <div class="consumers-table">
        <Core.data_table columns={@table_columns} rows={@consumer_rows} empty_message="No consumers found" sort_by={@sort_by} sort_dir={@sort_dir} />
      </div>
    </div>
    """
  end

  defp build_table_columns do
    [
      %{label: "Consumer", key: :consumer, sortable?: true},
      %{label: "Requests", key: :requests, sortable?: true},
      %{label: "Error Rate", key: :error_rate, sortable?: true},
      %{label: "Avg Latency", key: :avg_latency, sortable?: true},
      %{label: "Last Seen", key: :last_seen, sortable?: true}
    ]
  end

  defp build_consumer_row(consumer) do
    requests = consumer.requests || 0
    errors = consumer.errors || 0
    error_rate = if requests > 0, do: errors / requests * 100, else: 0.0

    %{
      consumer: consumer.consumer,
      requests: format_number(requests),
      error_rate: format_percentage(error_rate),
      avg_latency: format_duration(consumer.avg_latency),
      last_seen: format_timestamp(consumer.last_seen)
    }
  end

  defp sort_consumers(consumers, sort_by, sort_dir) do
    sorted =
      case sort_by do
        "consumer" -> Enum.sort_by(consumers, & &1.consumer)
        "requests" -> Enum.sort_by(consumers, &(&1.requests || 0))
        "error_rate" ->
          Enum.sort_by(consumers, fn c ->
            req = c.requests || 0
            if req > 0, do: (c.errors || 0) / req, else: 0.0
          end)
        "avg_latency" -> Enum.sort_by(consumers, &(&1.avg_latency || 0))
        "last_seen" -> Enum.sort_by(consumers, &(&1.last_seen || 0))
        _ -> Enum.sort_by(consumers, &(&1.requests || 0))
      end

    if sort_dir == "desc", do: Enum.reverse(sorted), else: sorted
  end

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    Float.round(n, 1) |> then(&"#{&1}%")
  end

  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n, 2)}ms"
  defp format_duration(_), do: "-"
end
