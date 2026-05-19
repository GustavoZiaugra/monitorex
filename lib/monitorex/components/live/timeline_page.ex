defmodule Monitorex.Components.Live.TimelinePage do
  @moduledoc """
  Timeline Split-Pane LiveComponent — revamped.

  Groups events into time buckets, provides filter/search bar,
  and compact event items for better UX at scale.
  """

  use Phoenix.LiveComponent
  import Monitorex.Components.Live.Helpers, only: [format_timestamp: 1]

  alias Monitorex.ClusterPage
  alias Monitorex.HeaderRedactor
  alias Monitorex.Components.Core

  @page_size 100
  @initial_load 50

  @impl true
  def update(assigns, socket) do
    direction = assigns[:direction] || "outbound"
    selected_id = assigns[:selected] && String.to_integer(assigns[:selected])
    search_query = assigns[:search] || ""
    filter_status = assigns[:status] || ""
    filter_method = assigns[:method] || ""
    show_all = assigns[:show_all] == "true"

    all_events = list_events(direction, @page_size)
    filtered = apply_filters(all_events, search_query, filter_status, filter_method)
    display_limit = if show_all, do: @page_size, else: @initial_load
    display_events = Enum.take(filtered, display_limit)
    grouped = group_by_time(display_events)
    selected_event = find_selected(display_events, selected_id)
    total_matching = length(filtered)
    has_more = total_matching > display_limit

    socket =
      socket
      |> assign(:direction, direction)
      |> assign(:all_events, filtered)
      |> assign(:events, display_events)
      |> assign(:grouped_events, grouped)
      |> assign(:selected_event, selected_event)
      |> assign(:page_size, @page_size)
      |> assign(:initial_load, @initial_load)
      |> assign(:search_query, search_query)
      |> assign(:filter_status, filter_status)
      |> assign(:filter_method, filter_method)
      |> assign(:show_all, show_all)
      |> assign(:total_matching, total_matching)
      |> assign(:has_more, has_more)
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
    url = build_filter_url(socket, %{selected: id_str})
    send(self(), {:navigate, url})
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"search" => query}, socket) do
    url = build_filter_url(socket, %{search: query, selected: nil, show_all: nil})
    send(self(), {:navigate, url})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    url = build_filter_url(socket, %{status: status, selected: nil, show_all: nil})
    send(self(), {:navigate, url})
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_method", %{"method" => method}, socket) do
    url = build_filter_url(socket, %{method: method, selected: nil, show_all: nil})
    send(self(), {:navigate, url})
    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    url = build_filter_url(socket, %{show_all: "true"})
    send(self(), {:navigate, url})
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    base = "?page=timeline&direction=#{socket.assigns.direction}"
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
          <p class="page-subtitle">
            Real-time request/response inspector —
            <%= @total_matching %> events
            <span :if={@events != @all_events}>
              (showing <%= length(@events) %>)
            </span>
          </p>
        </div>
        <div class="page-header-actions">
          <Core.export_button page_name="timeline" />
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
          <!-- Filter Bar -->
          <div class="tl-filter-bar">
            <div class="tl-search-wrap">
              <svg class="tl-search-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
              </svg>
              <input
                type="text"
                class="tl-search-input"
                placeholder="Search host or path..."
                value={@search_query}
                phx-keyup="search"
                phx-debounce="300"
              />
              <button
                :if={@search_query != "" || @filter_status != "" || @filter_method != ""}
                phx-click="clear_filters"
                class="tl-clear-btn"
                title="Clear filters">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
              </button>
            </div>
            <div class="tl-filter-chips">
              <div class="tl-chip-group-label">Status</div>
              <div class="tl-chip-group">
                <button phx-click="filter_status" phx-value-status="" class={["tl-chip", if(@filter_status == "", do: "active")]}>All</button>
                <button phx-click="filter_status" phx-value-status="success" class={["tl-chip", "chip-success", if(@filter_status == "success", do: "active")]}>2xx</button>
                <button phx-click="filter_status" phx-value-status="redirect" class={["tl-chip", "chip-redirect", if(@filter_status == "redirect", do: "active")]}>3xx</button>
                <button phx-click="filter_status" phx-value-status="client_error" class={["tl-chip", "chip-client-error", if(@filter_status == "client_error", do: "active")]}>4xx</button>
                <button phx-click="filter_status" phx-value-status="server_error" class={["tl-chip", "chip-server-error", if(@filter_status == "server_error", do: "active")]}>5xx</button>
              </div>
            </div>
            <div class="tl-filter-chips">
              <div class="tl-chip-group-label">Method</div>
              <div class="tl-chip-group">
                <button phx-click="filter_method" phx-value-method="" class={["tl-chip", if(@filter_method == "", do: "active")]}>All</button>
                <button phx-click="filter_method" phx-value-method="GET" class={["tl-chip", "chip-get", if(@filter_method == "GET", do: "active")]}>GET</button>
                <button phx-click="filter_method" phx-value-method="POST" class={["tl-chip", "chip-post", if(@filter_method == "POST", do: "active")]}>POST</button>
                <button phx-click="filter_method" phx-value-method="PUT" class={["tl-chip", "chip-put", if(@filter_method == "PUT", do: "active")]}>PUT</button>
                <button phx-click="filter_method" phx-value-method="DELETE" class={["tl-chip", "chip-delete", if(@filter_method == "DELETE", do: "active")]}>DEL</button>
                <button phx-click="filter_method" phx-value-method="PATCH" class={["tl-chip", "chip-patch", if(@filter_method == "PATCH", do: "active")]}>PATCH</button>
              </div>
            </div>
          </div>

          <!-- Timeline List -->
          <div class="timeline-list" id="timeline-list">
            <%= if @grouped_events != [] do %>
              <div :for={group <- @grouped_events} class="tl-group">
                <div class="tl-group-header">
                  <span class="tl-group-label"><%= group.label %></span>
                  <span class="tl-group-count"><%= length(group.events) %></span>
                </div>
                <div :for={event <- group.events} class={[
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
                      <%= truncate_text(event.full_url || event.path || "-", 45) %>
                    </div>
                    <div class="tl-meta">
                      <span class={["tl-status", status_dot_class(event.status_class)]}>
                        <%= event.status || "---" %>
                      </span>
                      <span class="tl-latency"><%= format_duration(event.duration_ms) %></span>
                      <span class="tl-time"><%= format_timestamp(event.timestamp) %></span>
                      <span :if={event.host} class="tl-host"><%= event.host %></span>
                    </div>
                  </div>
                  <div class="tl-chevron">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <polyline points="9 18 15 12 9 6" />
                    </svg>
                  </div>
                </div>
              </div>
              <button :if={@has_more} phx-click="load_more" class="tl-load-more">
                Load <%= min(50, @total_matching - length(@events)) %> more events
            (<%= @total_matching - length(@events) %> remaining)
              </button>
            <% else %>
              <div class="timeline-empty">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
                  <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
                </svg>
                <p>No matching <%= @direction %> events</p>
                <button :if={@search_query != "" || @filter_status != "" || @filter_method != ""}
                  phx-click="clear_filters" class="tl-chip active">
                  Clear filters
                </button>
              </div>
            <% end %>
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

  # ── Filter URL builder ──

  defp build_filter_url(socket, overrides) do
    assigns = socket.assigns

    params =
      %{
        direction: Map.get(assigns, :direction, "outbound"),
        search: overrides[:search] || Map.get(assigns, :search_query, "") || "",
        status: overrides[:status] || Map.get(assigns, :filter_status, "") || "",
        method: overrides[:method] || Map.get(assigns, :filter_method, "") || "",
        show_all: overrides[:show_all] || if(Map.get(assigns, :show_all), do: "true", else: nil),
        selected: overrides[:selected] || Map.get(assigns, :selected)
      }
      |> Map.reject(fn {_, v} -> is_nil(v) || v == "" end)

    "?page=timeline" <>
      if(params[:direction] != "outbound", do: "&direction=#{params[:direction]}", else: "") <>
      if(params[:search] && params[:search] != "",
        do: "&search=#{URI.encode(params[:search])}",
        else: ""
      ) <>
      if(params[:status] && params[:status] != "", do: "&status=#{params[:status]}", else: "") <>
      if(params[:method] && params[:method] != "", do: "&method=#{params[:method]}", else: "") <>
      if(params[:show_all], do: "&show_all=true", else: "") <>
      if params[:selected], do: "&selected=#{params[:selected]}", else: ""
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

  # ── Filtering ──

  defp apply_filters(events, search, status_class, method) do
    events
    |> maybe_filter_by_search(search)
    |> maybe_filter_by_status(status_class)
    |> maybe_filter_by_method(method)
  end

  defp maybe_filter_by_search(events, ""), do: events

  defp maybe_filter_by_search(events, query) do
    q = String.downcase(query)

    Enum.filter(events, fn e ->
      (e.host && String.contains?(String.downcase(e.host), q)) or
        (e.path && String.contains?(String.downcase(e.path), q)) or
        (e.full_url && String.contains?(String.downcase(e.full_url), q))
    end)
  end

  defp maybe_filter_by_status(events, ""), do: events

  defp maybe_filter_by_status(events, status_class) do
    sc = String.to_existing_atom(status_class)
    Enum.filter(events, fn e -> e.status_class == sc end)
  rescue
    _ -> events
  end

  defp maybe_filter_by_method(events, ""), do: events

  defp maybe_filter_by_method(events, method) do
    m = String.upcase(method)
    Enum.filter(events, fn e -> e.method && String.upcase(e.method) == m end)
  end

  # ── Time bucketing ──

  defp group_by_time(events) do
    now = System.system_time(:microsecond)

    events
    |> Enum.group_by(fn e -> bucket_label(now, e.timestamp) end)
    |> Enum.sort(fn {a_label, _}, {b_label, _} ->
      bucket_order(a_label) <= bucket_order(b_label)
    end)
    |> Enum.map(fn {label, items} -> %{label: label, events: items} end)
  end

  defp bucket_label(now, timestamp) when is_integer(timestamp) do
    secs = div(max(0, now - timestamp), 1_000_000)

    cond do
      secs <= 30 -> "Just now"
      secs <= 120 -> "1 min ago"
      secs <= 600 -> "5 min ago"
      secs <= 1800 -> "10 min ago"
      secs <= 3600 -> "30 min ago"
      true -> "Older"
    end
  end

  defp bucket_label(_now, _other), do: "Older"

  defp bucket_order("Just now"), do: 0
  defp bucket_order("1 min ago"), do: 1
  defp bucket_order("5 min ago"), do: 2
  defp bucket_order("10 min ago"), do: 3
  defp bucket_order("30 min ago"), do: 4
  defp bucket_order("Older"), do: 5

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
