defmodule Monitorex.DashboardLive do
  @moduledoc """
  Root LiveView for the Monitorex dashboard.

  Delegates rendering to the appropriate page component based on URL params.
  Handles automatic 2-second refresh when the socket is connected.

  ## Pages

    * `outbound` → OutboundOverviewPage
    * `outbound_recent` → OutboundRecentPage
    * `host` → HostDetailPage
    * `inbound` → InboundOverviewPage
    * `inbound_consumers` → InboundConsumersPage
    * `inbound_recent` → InboundRecentPage
    * `route` → RouteDetailPage
  """
  use Phoenix.LiveView

  alias Monitorex.Components.Live

  @pages %{
    "outbound" => Live.OutboundOverviewPage,
    "outbound_recent" => Live.OutboundRecentPage,
    "host" => Live.HostDetailPage,
    "inbound" => Live.InboundOverviewPage,
    "inbound_consumers" => Live.InboundConsumersPage,
    "inbound_recent" => Live.InboundRecentPage,
    "route" => Live.RouteDetailPage,
    "timeline" => Live.TimelinePage
  }

  @default_page "outbound"

  @impl true
  def mount(params, _session, socket) do
    socket = resolve_and_assign(socket, params)

    if connected?(socket) do
      Process.send_after(self(), :refresh, 2000)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = resolve_and_assign(socket, params)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, 2000)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:navigate, path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component id="page" module={@page} {@page_assigns} />
    """
  end

  @doc false
  def get_pages, do: @pages

  @doc false
  def default_page, do: @default_page

  @doc false
  def resolve_page(params) do
    case params do
      %{"page" => "host", "host" => _host} ->
        "host"

      %{"page" => "route", "host" => _route_key} ->
        "route"

      %{"page" => page} when is_binary(page) ->
        if Map.has_key?(@pages, page), do: page, else: @default_page

      %{} ->
        @default_page
    end
  end

  @doc false
  def build_page_assigns(params, "route") do
    params
    |> Map.drop(["page"])
    |> atomize_keys()
    |> normalize_route_param()
  end

  @doc false
  def build_page_assigns(params, _page_name) do
    params
    |> Map.drop(["page"])
    |> atomize_keys()
  end

  defp resolve_and_assign(socket, params) do
    page_name = resolve_page(params)
    component = Map.get(@pages, page_name, @pages[@default_page])
    page_assigns = build_page_assigns(params, page_name)

    socket
    |> assign(:page, component)
    |> assign(:page_name, page_name)
    |> assign(:page_assigns, page_assigns)
  end

  defp normalize_route_param(assigns) do
    case assigns do
      %{host: route_key} -> Map.put(assigns, :route, route_key) |> Map.delete(:host)
      _ -> assigns
    end
  end

  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end
end
