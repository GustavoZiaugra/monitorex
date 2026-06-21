defmodule Monitorex.Components.Live.RenderTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.{
    HostDetailPage,
    InboundConsumersPage,
    InboundOverviewPage,
    InboundRecentPage,
    OutboundOverviewPage,
    OutboundRecentPage,
    RouteDetailPage,
    TimelinePage
  }

  alias Monitorex.LiveComponentFixtures

  @tables [
    :monitorex_outbound_hosts,
    :monitorex_outbound_endpoints,
    :monitorex_outbound_recent,
    :monitorex_inbound_routes,
    :monitorex_inbound_consumers,
    :monitorex_inbound_recent
  ]

  setup do
    LiveComponentFixtures.reset_ets_tables(@tables)
    :ok
  end

  test "renders OutboundOverviewPage" do
    html = render_component(OutboundOverviewPage, %{id: "outbound"})
    assert html =~ "Outbound Overview"
  end

  test "renders OutboundRecentPage" do
    html = render_component(OutboundRecentPage, %{id: "outbound_recent"})
    assert html =~ "Recent Outbound Requests"
  end

  test "renders HostDetailPage" do
    html = render_component(HostDetailPage, %{id: "host", host: "api.example.com"})
    assert html =~ "api.example.com"
  end

  test "renders InboundOverviewPage" do
    html = render_component(InboundOverviewPage, %{id: "inbound"})
    assert html =~ "Inbound Overview"
  end

  test "renders InboundConsumersPage" do
    html = render_component(InboundConsumersPage, %{id: "inbound_consumers"})
    assert html =~ "Inbound Consumers"
  end

  test "renders InboundRecentPage" do
    html = render_component(InboundRecentPage, %{id: "inbound_recent"})
    assert html =~ "Recent Inbound Requests"
  end

  test "renders RouteDetailPage" do
    html = render_component(RouteDetailPage, %{id: "route", route: "GET:/api/users"})
    assert html =~ "GET:/api/users"
  end

  test "renders TimelinePage" do
    html = render_component(TimelinePage, %{id: "timeline"})
    assert html =~ "Timeline"
  end
end
