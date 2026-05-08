defmodule Monitorex.Components.Core do
  @moduledoc """
  Reusable UI components for the Monitorex dashboard.

  Provides a cohesive design system with dark theme, responsive layout,
  and accessible touch-friendly targets.

  Components:
    * `data_table/1` — sortable, striped, responsive data table
    * `summary_card/1` — card with icon, label, value, trend
    * `status_badge/1` — color-coded HTTP status badge
    * `node_selector/1` — dropdown node selector
    * `page_header/1` — page title with optional subtitle and actions
    * `metric_tile/1` — compact metric display
    * `pagination/1` — page navigation with prev/next and numbered buttons
    * `back_link/1` — navigation back link
  """

  use Phoenix.Component

  @doc """
  Renders a sortable, striped data table with responsive card layout.

  ## Assigns

    * `columns` — list of maps with `:label`, `:key`, and optional `:sortable?` (boolean)
    * `rows` — list of maps (each map has keys matching those in columns)
    * `empty_message` — string to show when there are no rows

  ## Events

    * `"sort"` — sent when a sortable column header is clicked, with the column key as the value
  """
  attr(:columns, :list, required: true)
  attr(:rows, :list, default: [])
  attr(:empty_message, :string, default: "No data")
  attr(:sort_by, :string, default: nil)
  attr(:sort_dir, :string, default: nil)

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
  Renders a summary card with icon, label, value, and optional trend indicator.

  ## Assigns

    * `label` — card label string
    * `value` — display value string
    * `trend` — optional `:up` or `:down` atom for trend icon
    * `icon` — optional SVG icon HTML string (default: chart icon)
    * `class` — additional CSS classes
  """
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:trend, :atom, values: [:up, :down, nil], default: nil)
  attr(:icon, :string, default: nil)
  attr(:class, :string, default: "")

  def summary_card(assigns) do
    ~H"""
    <div class={["card summary-card", @class]}>
      <div class="summary-card-icon">
        <%= if @icon do %>
          <%= Phoenix.HTML.raw(@icon) %>
        <% else %>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="18" y1="20" x2="18" y2="10" />
            <line x1="12" y1="20" x2="12" y2="4" />
            <line x1="6" y1="20" x2="6" y2="14" />
          </svg>
        <% end %>
      </div>
      <div class="summary-card-body">
        <div class="summary-card-label"><%= @label %></div>
        <div class="summary-card-value"><%= @value %></div>
        <div :if={@trend} class="summary-card-trend">
          <span class={if @trend == :up, do: "trend-up", else: "trend-down"}>
            <%= if @trend == :up do %>↑<% else %>↓<% end %>
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact metric tile.

  ## Assigns

    * `label` — metric label
    * `value` — metric value string
    * `class` — additional CSS classes
  """
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:class, :string, default: "")

  def metric_tile(assigns) do
    ~H"""
    <div class={["metric-tile", @class]}>
      <div class="metric-tile-label"><%= @label %></div>
      <div class="metric-tile-value"><%= @value %></div>
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
  attr(:status, :integer, required: true)

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
  attr(:nodes, :list, required: true)
  attr(:selected, :string, default: "")
  attr(:event, :string, default: "select_node")

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

  @doc """
  Renders a page header with title, optional subtitle, and actions slot.

  ## Assigns

    * `title` — page title string
    * `subtitle` — optional subtitle string
    * `inner_block` — optional content for the actions area (right side)
  """
  attr(:title, :string, required: true)
  attr(:subtitle, :string, default: nil)

  slot(:inner_block, required: false)

  def page_header(assigns) do
    ~H"""
    <div class="page-header">
      <div>
        <h2><%= @title %></h2>
        <p :if={@subtitle} class="page-subtitle"><%= @subtitle %></p>
      </div>
      <div :if={assigns[:inner_block]} class="page-header-actions">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a pagination control.

  ## Assigns

    * `current` — current page number (integer)
    * `total` — total number of pages (integer)
    * `event` — event name to send on page change (default: "go_page")
  """
  attr(:current, :integer, required: true)
  attr(:total, :integer, required: true)
  attr(:event, :string, default: "go_page")

  def pagination(assigns) do
    ~H"""
    <div :if={@total > 1} class="pagination">
      <button class="page-btn" :if={@current > 1} phx-click={@event} phx-value-page={@current - 1} disabled={@current <= 1}>
        ‹ Prev
      </button>

      <button :for={page <- visible_pages(@current, @total)}
        class={["page-btn", if(page == @current, do: "active")]}
        phx-click={@event} phx-value-page={page}
        disabled={page == @current}>
        <%= page %>
      </button>

      <button class="page-btn" :if={@current < @total} phx-click={@event} phx-value-page={@current + 1} disabled={@current >= @total}>
        Next ›
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

  @doc """
  Renders a back link for detail pages.

  ## Assigns

    * `to` — the URL to navigate back to
    * `label` — link text (default: "Back")
  """
  attr(:to, :string, required: true)
  attr(:label, :string, default: "Back")

  def back_link(assigns) do
    ~H"""
    <a href={@to} class="back-link">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <line x1="19" y1="12" x2="5" y2="12" />
        <polyline points="12 19 5 12 12 5" />
      </svg>
      <%= @label %>
    </a>
    """
  end
end
