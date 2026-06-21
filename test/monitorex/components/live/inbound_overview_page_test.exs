defmodule Monitorex.Components.Live.InboundOverviewPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.InboundOverviewPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders summary cards with zero values when no routes" do
      html = render_component(InboundOverviewPage, %{id: "test"})

      assert html =~ "Inbound Overview"
      assert html =~ "Total Requests"
      assert html =~ "Routes"
      assert html =~ "Error Rate"
      assert html =~ "0%"
    end

    test "renders routes table with empty state" do
      html = render_component(InboundOverviewPage, %{id: "test"})

      assert html =~ "Method"
      assert html =~ "Route"
      assert html =~ "Requests"
      assert html =~ "P95"
      assert html =~ "No routes found"
    end

    test "renders routes with real data" do
      insert_inbound_event(method: "GET", path: "/api/items", duration_ms: 15.0)

      insert_inbound_event(
        method: "POST",
        path: "/api/orders",
        status: 500,
        status_class: :server_error,
        duration_ms: 45.0
      )

      html = render_component(InboundOverviewPage, %{id: "test"})

      assert html =~ "GET"
      assert html =~ "POST"
      assert html =~ "/api/items"
      assert html =~ "/api/orders"
      assert html =~ "2"
    end
  end

  describe "handle_event/3" do
    test "navigate event sends navigation message" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          routes: [],
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               InboundOverviewPage.handle_event("navigate", %{"path" => "/route/GET:/api"}, socket)

      assert_received {:navigate, "/route/GET:/api"}
    end

    test "sort event toggles direction" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          routes: [],
          sort_by: "requests",
          sort_dir: "desc"
        }
      }

      assert {:noreply, _socket} =
               InboundOverviewPage.handle_event("sort", %{"key" => "requests"}, socket)

      assert_received {:navigate, url}
      assert url =~ "sort_by=requests"
      assert url =~ "sort_dir=asc"
    end
  end

  describe "sorting branches" do
    test "sorts by method, path, requests, p95 and unknown keys" do
      :ets.insert(:monitorex_inbound_routes, {
        "GET:/api/a",
        %{method: "GET", path: "/api/a", requests: 10, errors: 0, total_duration: 100.0, p95: 20.0, last_seen: System.system_time(:microsecond)}
      })

      :ets.insert(:monitorex_inbound_routes, {
        "POST:/api/b",
        %{method: "POST", path: "/api/b", requests: 5, errors: 1, total_duration: 50.0, p95: 10.0, last_seen: System.system_time(:microsecond)}
      })

      for sort_by <- ["method", "path", "requests", "p95", "unknown"] do
        html = render_component(InboundOverviewPage, %{id: "test", sort_by: sort_by, sort_dir: "asc"})
        assert html =~ "GET"
        assert html =~ "POST"
      end
    end
  end
end
