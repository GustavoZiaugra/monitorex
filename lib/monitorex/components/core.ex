defmodule Monitorex.Components.Core do
  @moduledoc """
  Reusable UI components for the Monitorex dashboard.

  Provides:
    * `data_table/1` — sortable, striped data table
    * `summary_card/1` — card with label, value, and optional trend indicator
    * `status_badge/1` — color-coded HTTP status badge
    * `node_selector/1` — drop-down selector for nodes/hosts
  """

  use Phoenix.Component

  @doc """
  Renders a sortable, striped data table.

  ## Assigns

    * `columns` — list of maps with `:label`, `:key`, and optional `:sortable?` (boolean)
    * `rows` — list of maps (each map has keys matching those in columns)
    * `empty_message` — string to show when there are no rows

  ## Events

    * `"sort"` — sent when a sortable column header is clicked, with the column key as the value
  """
  attr :columns, :list, required: true
  attr :rows, :list, default: []
  attr :empty_message, :string, default: "No data"
  attr :sort_by, :string, default: nil
  attr :sort_dir, :string, default: nil

  def data_table(assigns) do
    ~H"""
    <div class="data-table-container">
      <table class="data-table">
        <thead>
          <tr>
            <th :for={col <- @columns} class={["data-table-th", if(col[:sortable?], do: "sortable")]} phx-click={if(col[:sortable?], do: "sort")} phx-value-key={col[:key]}>
              <%= col.label %>
              <%= if @sort_by == col[:key] do %>
                <span class="sort-indicator"><%= if @sort_dir == "asc", do: "▲", else: "▼" %></span>
              <% end %>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} class="data-table-row">
            <td :for={col <- @columns} class="data-table-td" data-label={col.label}>
              <%= Map.get(row, col.key) %>
            </td>
          </tr>
          <tr :if={@rows == []}>
            <td colspan={length(@columns)} class="data-table-empty">
              <%= @empty_message %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a summary card with label, value, and optional trend indicator.

  ## Assigns

    * `label` — card label string
    * `value` — display value string
    * `trend` — optional `:up` or `:down` atom for trend icon
    * `class` — additional CSS classes
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :trend, :atom, values: [:up, :down, nil], default: nil
  attr :class, :string, default: ""

  def summary_card(assigns) do
    ~H"""
    <div class={["card summary-card", @class]}>
      <div class="summary-card-icon">
        <%= if @trend == :up do %>
          <span class="trend-up">&#9650;</span>
        <% end %>
        <%= if @trend == :down do %>
          <span class="trend-down">&#9660;</span>
        <% end %>
      </div>
      <div class="summary-card-body">
        <div class="summary-card-label"><%= @label %></div>
        <div class="summary-card-value"><%= @value %></div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a color-coded HTTP status badge.

  ## Assigns

    * `status` — integer HTTP status code

  Colors:
    * 2xx — green
    * 3xx — blue
    * 4xx — yellow
    * 5xx — red
  """
  attr :status, :integer, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge",
      status_class(@status)
    ]}>
      <%= @status %> <%= status_text(@status) %>
    </span>
    """
  end

  defp status_class(status) when status >= 200 and status < 300, do: "badge-success"
  defp status_class(status) when status >= 300 and status < 400, do: "badge-redirect"
  defp status_class(status) when status >= 400 and status < 500, do: "badge-client-error"
  defp status_class(status) when status >= 500, do: "badge-server-error"
  defp status_class(_), do: "badge-default"

  defp status_text(200), do: "OK"
  defp status_text(201), do: "Created"
  defp status_text(204), do: "No Content"
  defp status_text(301), do: "Moved Permanently"
  defp status_text(302), do: "Found"
  defp status_text(304), do: "Not Modified"
  defp status_text(400), do: "Bad Request"
  defp status_text(401), do: "Unauthorized"
  defp status_text(403), do: "Forbidden"
  defp status_text(404), do: "Not Found"
  defp status_text(405), do: "Method Not Allowed"
  defp status_text(409), do: "Conflict"
  defp status_text(422), do: "Unprocessable Entity"
  defp status_text(429), do: "Too Many Requests"
  defp status_text(500), do: "Internal Server Error"
  defp status_text(502), do: "Bad Gateway"
  defp status_text(503), do: "Service Unavailable"
  defp status_text(504), do: "Gateway Timeout"
  defp status_text(_), do: "Unknown"

  @doc """
  Renders a dropdown node selector.

  ## Assigns

    * `nodes` — list of node names (strings)
    * `selected` — currently selected node (string)
    * `event` — event name to send on change
  """
  attr :nodes, :list, required: true
  attr :selected, :string, default: ""
  attr :event, :string, default: "select_node"

  def node_selector(assigns) do
    ~H"""
    <select class="node-selector" phx-change={@event}>
      <option value="">All Nodes</option>
      <option :for={node <- @nodes} value={node} selected={node == @selected}>
        <%= node %>
      </option>
    </select>
    """
  end
end
