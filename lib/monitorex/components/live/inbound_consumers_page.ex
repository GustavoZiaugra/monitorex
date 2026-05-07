defmodule Monitorex.Components.Live.InboundConsumersPage do
  @moduledoc """
  LiveComponent that renders the inbound consumers dashboard.

  Displays a summary card with total consumer count and a data table
  with per-consumer statistics (requests, error rate, average latency).
  """
  use Phoenix.LiveComponent

  alias Monitorex.Storage
  alias Monitorex.Components.Core

  @impl true
  def update(_assigns, socket) do
    consumers = Storage.list_consumers()

    consumer_rows = Enum.map(consumers, &build_consumer_row/1)

    socket =
      socket
      |> assign(:consumers, consumers)
      |> assign(:consumer_rows, consumer_rows)
      |> assign(:consumer_count, length(consumers))

    {:ok, socket}
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
            <tr :for={row <- @consumer_rows} class="data-table-row">
              <td class="data-table-td"><%= row.consumer %></td>
              <td class="data-table-td"><%= row.requests %></td>
              <td class="data-table-td"><%= row.error_rate %></td>
              <td class="data-table-td"><%= row.avg_latency %></td>
              <td class="data-table-td"><%= row.last_seen %></td>
            </tr>
            <tr :if={@consumer_rows == []}>
              <td colspan="5" class="data-table-empty">No consumers found</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
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

  defp format_number(n) when is_number(n), do: Integer.to_string(round(n))
  defp format_number(_), do: "0"

  defp format_percentage(n) when is_number(n) do
    Float.round(n, 1) |> then(&"#{&1}%")
  end
  defp format_percentage(_), do: "0%"

  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n, 2)}ms"
  defp format_duration(_), do: "-"

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
end
