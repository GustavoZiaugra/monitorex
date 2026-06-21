defmodule Monitorex.Components.Live.RouteDetailPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.RouteDetailPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders empty state when route has no data" do
      html = render_component(RouteDetailPage, %{id: "test", route: "POST:/api/users"})

      assert html =~ "POST:/api/users"
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

      assert html =~ "badkey"
    end

    test "renders route metrics, consumers and recent events when data exists" do
      insert_inbound_event(method: "GET", path: "/api/items", duration_ms: 15.0)

      insert_inbound_event(
        method: "GET",
        path: "/api/items",
        status: 500,
        status_class: :server_error,
        duration_ms: 45.0
      )

      html = render_component(RouteDetailPage, %{id: "test", route: "GET:/api/items"})

      assert html =~ "GET:/api/items"
      assert html =~ "svc-a"
      assert html =~ "/api/items"
      assert html =~ "2"
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

      assert {:noreply, _socket} =
               RouteDetailPage.handle_event("sort", %{"key" => "requests"}, socket)

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

      assert {:noreply, _socket} =
               RouteDetailPage.handle_event("sort", %{"key" => "consumer"}, socket)

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

    test "go_recent_page event navigates with page" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          route_key: "GET:/test",
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               RouteDetailPage.handle_event("go_recent_page", %{"page" => "3"}, socket)

      assert_received {:navigate, url}
      assert url =~ "recent_page=3"
      assert url =~ "host=GET:/test"
    end
  end
end
