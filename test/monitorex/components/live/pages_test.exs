defmodule Monitorex.Components.Live.PagesTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.OutboundRecentPage
  alias Monitorex.Components.Live.HostDetailPage
  alias Monitorex.Components.Live.InboundOverviewPage
  alias Monitorex.Components.Live.InboundConsumersPage
  alias Monitorex.Components.Live.InboundRecentPage
  alias Monitorex.Components.Live.RouteDetailPage

  describe "OutboundRecentPage" do
    test "renders empty state and filter controls" do
      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "Recent Outbound Requests"
      assert html =~ "Time"
      assert html =~ "Method"
      assert html =~ "URL"
      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "No recent outbound requests"
      assert html =~ "2xx"
      assert html =~ "3xx"
      assert html =~ "4xx"
      assert html =~ "5xx"
    end

    test "renders with host filter" do
      html = render_component(OutboundRecentPage, %{id: "test", host: "api.example.com"})
      assert html =~ "Recent Outbound Requests"
    end

    test "renders with status_class filter" do
      html = render_component(OutboundRecentPage, %{id: "test", status_class: "success"})
      assert html =~ "Recent Outbound Requests"
    end
  end

  describe "HostDetailPage" do
    test "renders empty state with all summary cards" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "Host: api.example.com"
      assert html =~ "Total Requests"
      assert html =~ "Endpoints"
      assert html =~ "Avg Latency"
      assert html =~ "Error Rate"
    end

    test "renders endpoint table columns" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "Endpoints"
      assert html =~ "Path"
      assert html =~ "Requests"
      assert html =~ "Avg"
      assert html =~ "Error Rate"
      assert html =~ "No endpoints found"
    end

    test "renders recent requests table" do
      html = render_component(HostDetailPage, %{id: "test", host: "api.example.com"})

      assert html =~ "Recent Requests"
      assert html =~ "No recent requests for this host"
    end
  end

  describe "InboundOverviewPage" do
    test "renders summary cards and empty table" do
      html = render_component(InboundOverviewPage, %{id: "test"})

      assert html =~ "Inbound Overview"
      assert html =~ "Total Requests"
      assert html =~ "Routes"
      assert html =~ "Error Rate"
      assert html =~ "Method"
      assert html =~ "Route"
      assert html =~ "P95"
      assert html =~ "No routes found"
      assert html =~ "0%"
    end
  end

  describe "InboundConsumersPage" do
    test "renders summary card and empty table" do
      html = render_component(InboundConsumersPage, %{id: "test"})

      assert html =~ "Inbound Consumers"
      assert html =~ "Total Consumers"
      assert html =~ "Consumer"
      assert html =~ "Requests"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
      assert html =~ "Last Seen"
      assert html =~ "No consumers found"
    end
  end

  describe "InboundRecentPage" do
    test "renders empty state and filter controls" do
      html = render_component(InboundRecentPage, %{id: "test"})

      assert html =~ "Recent Inbound Requests"
      assert html =~ "Time"
      assert html =~ "Consumer"
      assert html =~ "Method"
      assert html =~ "Route"
      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "No recent inbound requests"
      assert html =~ "All Consumers"
      assert html =~ "All Routes"
    end

    test "renders with filters" do
      html = render_component(InboundRecentPage, %{
        id: "test",
        status_class: "error",
        consumer: "myapp",
        route: "GET:/api/users"
      })

      assert html =~ "Recent Inbound Requests"
    end
  end

  describe "RouteDetailPage" do
    test "renders empty state and summary" do
      html = render_component(RouteDetailPage, %{id: "test", route: "POST:/api/users"})

      assert html =~ "Route: POST /api/users"
      assert html =~ "Total Requests"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
      assert html =~ "Top Consumers"
      assert html =~ "Recent Requests"
      assert html =~ "No consumers found"
      assert html =~ "No recent requests for this route"
    end

    test "handles malformed route key" do
      html = render_component(RouteDetailPage, %{id: "test", route: "badkey"})
      assert html =~ "Route: ? badkey"
    end
  end
end
