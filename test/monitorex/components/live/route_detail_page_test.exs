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
      assert html =~ "No consumers found"
      assert html =~ "No recent requests for this route"
    end

    test "handles malformed route key" do
      html = render_component(RouteDetailPage, %{id: "test", route: "badkey"})

      assert html =~ "Route: ? badkey"
    end
  end

  describe "handle_event/3" do
    test "sort event toggles direction for same key" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          route_key: "GET:/test",
          sort_by: "requests",
          sort_dir: "asc"
        }
      }

      assert {:noreply, _socket} = RouteDetailPage.handle_event("sort", %{"key" => "requests"}, socket)
      assert_received {:navigate, url}
      assert url =~ "sort_by=requests"
      assert url =~ "sort_dir=desc"
    end

    test "sort event changes to new key with ascending direction" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          route_key: "GET:/test",
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} = RouteDetailPage.handle_event("sort", %{"key" => "consumer"}, socket)
      assert_received {:navigate, url}
      assert url =~ "sort_by=consumer"
      assert url =~ "sort_dir=asc"
    end

    test "sort event ignores invalid keys" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          route_key: "GET:/test",
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert_raise FunctionClauseError, fn ->
        RouteDetailPage.handle_event("sort", %{"key" => "invalid"}, socket)
      end
    end
  end
end
