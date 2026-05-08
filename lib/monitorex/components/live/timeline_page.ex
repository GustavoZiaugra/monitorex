defmodule Monitorex.Components.Live.TimelinePage do
  @moduledoc """
  Timeline Split-Pane LiveComponent — Concept A.

  Renders a vertical timeline of recent HTTP requests on the left pane.
  Clicking a timeline item shows full request/response details on the right pane,
  including headers (with configurable redaction via HeaderRedactor).

  ## Layout

      ┌──────────────────────────────────────────────────┐
      │  Timeline         │  Detail                      │
      │  ┌─────────────┐  │  ┌──────────────────────────┐│
      │  │ GET /api/u  │  │  │ Method: GET              ││
      │  │ 200 12.5ms  │  │  │ Host: api.example.com    ││
      │  │ 10:23:45    │  │  │ URL: https://api.ex...   ││
      │  ├─────────────┤  │  │ Status: 200 OK           ││
      │  │ POST /api   │  │  │ Duration: 12.5ms         ││
      │  │ 201 3.2ms   │  │  │ Timestamp: 10:23:45      ││
      │  │ 10:23:44    │  │  ├──────────────────────────┤│
      │  ├─────────────┤  │  │ Request Headers           ││
      │  │ GET /api/v  │  │  │  authorization: ••••re.. ││
      │  │ 404 0.5ms   │  │  │  content-type: app/json   ││
      │  │ 10:23:43    │  │  ├──────────────────────────┤│
      │  └─────────────┘  │  │ Response Headers          ││
      │                   │  │  x-request-id: abc-123   ││
      │                   │  │  set-cookie: ••••reda..  ││
      │                   │  ├──────────────────────────┤│
      │                   │  │ Response Body             ││
      │                   │  │ {"users": [...], "p...   ││
      │                   │  └──────────────────────────┘│
      └──────────────────────────────────────────────────┘

  ## Interaction

    * Click a timeline item → select it, detail pane updates
    * Direction tabs (Outbound / Inbound) → filter by direction
    * Auto-refresh — new events appear at the top
  """

  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.ClusterPage
  alias Monitorex.HeaderRedactor
  alias Monitorex.Components.Core

  @page_size 100

  @impl true
  def update(assigns, socket) do
    direction = assigns[:direction] || "outbound"
    selected_id = assigns[:selected] && String.to_integer(assigns[:selected])

    events = list_events(direction, @page_size)
    selected_event = find_selected(events, selected_id)

    socket =
      socket
      |> assign(:direction, direction)
      |> assign(:events, events)
      |> assign(:selected_event, selected_event)
      |> assign(:page_size, @page_size)
      |> assign(:redacted_headers, HeaderRedactor.default_redacted_headers())

    {:ok, socket}
  end

  @impl true
  def handle_event("select_direction", %{"direction" => dir}, socket) do
    base = "?page=timeline&direction=#{dir}"
    send(self(), {:navigate, base})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_event", %{"id" => id_str}, socket) do
    base = "?page=timeline&direction=#{socket.assigns.direction}&selected=#{id_str}"
    send(self(), {:navigate, base})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="timeline-page">
      <div class="page-header">
        <div>
          <h2>Request Timeline</h2>
          <p class="page-subtitle">Real-time request/response inspector with header redaction</p>
        </div>
        <div class="page-header-actions">
          <div class="timeline-tabs">
            <button
              phx-click="select_direction" phx-value-direction="outbound"
              class={["timeline-tab", if(@direction == "outbound", do: "active")]}>
              Outbound
            </button>
            <button
              phx-click="select_direction" phx-value-direction="inbound"
              class={["timeline-tab", if(@direction == "inbound", do: "active")]}>
              Inbound
            </button>
          </div>
        </div>
      </div>

      <div class="timeline-split">
        <!-- Left Pane: Timeline List -->
        <div class="timeline-list-pane">
          <div class="timeline-list-header">
            <span class="timeline-count"><%= length(@events) %> events</span>
          </div>
          <div class="timeline-list" id="timeline-list">
            <div :for={event <- @events} class={[
              "timeline-item",
              if(@selected_event && event.timestamp == @selected_event.timestamp, do: "selected"),
              "tl-#{event.direction || "outbound"}",
              "tl-#{event.status_class || :default}"
            ]} phx-click="select_event" phx-value-id={event.timestamp}>
              <div class="tl-method">
                <span class={["method-badge", method_class(event.method)]}>
                  <%= event.method || "-" %>
                </span>
              </div>
              <div class="tl-content">
                <div class="tl-url">
                  <%= truncate_text(event.full_url || event.path || "-", 50) %>
                </div>
                <div class="tl-meta">
                  <span class={["tl-status", status_dot_class(event.status_class)]}>
                    <%= event.status || "---" %>
                  </span>
                  <span class="tl-latency"><%= format_duration(event.duration_ms) %></span>
                  <span class="tl-time"><%= format_timestamp(event.timestamp) %></span>
                </div>
              </div>
              <div class="tl-chevron">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <polyline points="9 18 15 12 9 6" />
                </svg>
              </div>
            </div>
            <div :if={@events == []} class="timeline-empty">
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
              </svg>
              <p>No recent <%= @direction %> events</p>
            </div>
          </div>
        </div>

        <!-- Right Pane: Event Detail -->
        <div class="timeline-detail-pane">
          <%= if @selected_event do %>
            <div class="detail-header">
              <h3>Request Details</h3>
              <span class={["detail-dir-badge", "dir-#{@selected_event.direction}"]}>
                <%= @selected_event.direction %>
              </span>
            </div>

            <div class="detail-meta-grid">
              <div class="detail-meta-item">
                <span class="meta-label">Method</span>
                <span class={["meta-value", method_class(@selected_event.method)]}>
                  <%= @selected_event.method || "-" %>
                </span>
              </div>
              <div class="detail-meta-item">
                <span class="meta-label">Host</span>
                <span class="meta-value mono"><%= @selected_event.host || "-" %></span>
              </div>
              <div class="detail-meta-item full-width">
                <span class="meta-label">URL</span>
                <span class="meta-value mono break-all"><%= @selected_event.full_url || @selected_event.path || "-" %></span>
              </div>
              <div class="detail-meta-item">
                <span class="meta-label">Status</span>
                <span class="meta-value"><Core.status_badge status={@selected_event.status || 0} /></span>
              </div>
              <div class="detail-meta-item">
                <span class="meta-label">Duration</span>
                <span class="meta-value"><%= format_duration(@selected_event.duration_ms) %></span>
              </div>
              <div class="detail-meta-item">
                <span class="meta-label">Timestamp</span>
                <span class="meta-value mono"><%= format_timestamp(@selected_event.timestamp) %></span>
              </div>
              <div class="detail-meta-item" :if={@selected_event.error}>
                <span class="meta-label">Error</span>
                <span class="meta-value error-text"><%= @selected_event.error %></span>
              </div>
            </div>

            <!-- Request Headers -->
            <div class="detail-section">
              <div class="section-header">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="16 3 21 3 21 8" /><line x1="4" y1="20" x2="21" y2="3" /><polyline points="21 16 21 21 16 21" /><line x1="15" y1="15" x2="21" y2="21" /><line x1="4" y1="4" x2="9" y2="9" />
                </svg>
                <span>Request Headers</span>
              </div>
              <%= if @selected_event.request_headers && @selected_event.request_headers != [] do %>
                <div class="headers-list">
                  <div :for={h <- redact_headers(@selected_event.request_headers, @redacted_headers)} class="header-row">
                    <span class="header-key"><%= elem(h, 0) %></span>
                    <span class={[ "header-value", if(redacted?(elem(h, 1)), do: "redacted") ]}><%= elem(h, 1) %></span>
                  </div>
                </div>
              <% else %>
                <p class="detail-empty">No request headers captured</p>
              <% end %>
            </div>

            <!-- Response Headers -->
            <div class="detail-section">
              <div class="section-header">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="16 3 21 3 21 8" /><line x1="4" y1="20" x2="21" y2="3" /><polyline points="21 16 21 21 16 21" /><line x1="15" y1="15" x2="21" y2="21" /><line x1="4" y1="4" x2="9" y2="9" />
                </svg>
                <span>Response Headers</span>
              </div>
              <%= if @selected_event.response_headers && @selected_event.response_headers != [] do %>
                <div class="headers-list">
                  <div :for={h <- redact_headers(@selected_event.response_headers, @redacted_headers)} class="header-row">
                    <span class="header-key"><%= elem(h, 0) %></span>
                    <span class={[ "header-value", if(redacted?(elem(h, 1)), do: "redacted") ]}><%= elem(h, 1) %></span>
                  </div>
                </div>
              <% else %>
                <p class="detail-empty">No response headers captured</p>
              <% end %>
            </div>

            <!-- Response Body -->
            <div class="detail-section">
              <div class="section-header">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="3" y="3" width="18" height="18" rx="2" ry="2" /><line x1="3" y1="9" x2="21" y2="9" /><line x1="9" y1="21" x2="9" y2="9" />
                </svg>
                <span>Response Body</span>
              </div>
              <%= if @selected_event.response_body do %>
                <pre class="body-block"><%= maybe_truncate_body(@selected_event.response_body) %></pre>
              <% else %>
                <p class="detail-empty">No response body captured</p>
              <% end %>
            </div>

            <!-- Request Body -->
            <div class="detail-section">
              <div class="section-header">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="3" y="3" width="18" height="18" rx="2" ry="2" /><line x1="3" y1="9" x2="21" y2="9" /><line x1="9" y1="21" x2="9" y2="9" />
                </svg>
                <span>Request Body</span>
              </div>
              <%= if @selected_event.request_body do %>
                <pre class="body-block"><%= maybe_truncate_body(@selected_event.request_body) %></pre>
              <% else %>
                <p class="detail-empty">No request body captured</p>
              <% end %>
            </div>
          <% else %>
            <div class="detail-empty-state">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="11" cy="11" r="8" />
                <line x1="21" y1="21" x2="16.65" y2="16.65" />
                <line x1="11" y1="8" x2="11" y2="14" />
                <line x1="8" y1="11" x2="14" y2="11" />
              </svg>
              <p>Select an event from the timeline to inspect its details</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Data fetching ──

  defp list_events("outbound", limit) do
    ClusterPage.list_recent_outbound(limit: limit)
  end

  defp list_events("inbound", limit) do
    ClusterPage.list_recent_inbound(limit: limit)
  end

  defp list_events(_dir, _limit), do: []

  defp find_selected(_events, nil), do: nil
  defp find_selected(events, id) do
    Enum.find(events, fn e -> e.timestamp == id end)
  end

  # ── Header redaction display ──

  defp redact_headers(nil, _redacted), do: []
  defp redact_headers(headers, redacted) do
    HeaderRedactor.redact_headers(headers, redacted)
  end

  defp redacted?(value) when is_binary(value) do
    String.contains?(value, "••••redacted••••")
  end

  defp redacted?(_), do: false

  # ── Formatting ──

  defp format_duration(nil), do: "-"
  defp format_duration(n) when is_number(n), do: "#{Float.round(n, 2)}ms"
  defp format_duration(_), do: "-"

  defp truncate_text(nil, _max), do: "-"
  defp truncate_text(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max - 3) <> "..."
    else
      text
    end
  end

  defp maybe_truncate_body(nil), do: ""
  defp maybe_truncate_body(body) when is_binary(body) do
    if String.length(body) > 2000 do
      String.slice(body, 0, 1997) <> "..."
    else
      body
    end
  end

  defp method_class(nil), do: "method-default"
  defp method_class(m) when is_binary(m) do
    case String.upcase(m) do
      "GET" -> "method-GET"
      "POST" -> "method-POST"
      "PUT" -> "method-PUT"
      "DELETE" -> "method-DELETE"
      "PATCH" -> "method-PATCH"
      _ -> "method-default"
    end
  end

  defp status_dot_class(nil), do: "status-dot-default"
  defp status_dot_class(:success), do: "status-dot-success"
  defp status_dot_class(:redirect), do: "status-dot-redirect"
  defp status_dot_class(:client_error), do: "status-dot-client-error"
  defp status_dot_class(:server_error), do: "status-dot-server-error"
  defp status_dot_class(_), do: "status-dot-default"
end
