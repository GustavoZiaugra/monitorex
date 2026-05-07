defmodule Monitorex.Components.Live.RouteDetailPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.RouteDetailPage

  describe "update/2" do
    test "renders empty state when route has no data" do
      html = render_component(RouteDetailPage, %{id: "test", route: "POST:/api/users"})

      assert html =~ "Route: POST /api/users"
      assert html =~ "Total Requests"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
    end

    test "renders consumers table with empty state" do
      html = render_component(RouteDetailPage, %{id: "test", route: "GET:/api/items"})

      assert html =~ "Top Consumers"
      assert html =~ "Consumer"
      assert html =~ "Requests"
      assert html =~ "Error Rate"
      assert html =~ "Avg Latency"
      assert html =~ "Last Seen"
    end

    test "renders recent requests table with empty state" do
      html = render_component(RouteDetailPage, %{id: "test", route: "GET:/api/items"})

      assert html =~ "Recent Requests"
      assert html =~ "No consumers found for this route"
      assert html =~ "No recent requests for this route"
    end

    test "handles malformed route key" do
      html = render_component(RouteDetailPage, %{id: "test", route: "badkey"})

      assert html =~ "Route: ? badkey"
    end
  end
end
