defmodule Monitorex.Components.Live.InboundRecentPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.InboundRecentPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders empty state when no events" do
      html = render_component(InboundRecentPage, %{id: "test"})

      assert html =~ "Recent Inbound Requests"
      assert html =~ "Time"
      assert html =~ "Consumer"
      assert html =~ "Method"
      assert html =~ "Route"
      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "No recent inbound requests"
    end

    test "renders filter controls" do
      html = render_component(InboundRecentPage, %{id: "test"})

      assert html =~ "2xx"
      assert html =~ "3xx"
      assert html =~ "4xx"
      assert html =~ "5xx"
      assert html =~ "All Consumers"
      assert html =~ "All Routes"
    end

    test "renders with filters" do
      html =
        render_component(InboundRecentPage, %{
          id: "test",
          status_class: "2xx",
          consumer: "myapp",
          route: "GET:/api/users"
        })

      assert html =~ "Recent Inbound Requests"
    end

    test "renders recent inbound events" do
      insert_inbound_event(method: "GET", path: "/api/items", consumer: "svc-a")

      insert_inbound_event(
        method: "POST",
        path: "/api/orders",
        consumer: "svc-b",
        status: 500,
        status_class: :server_error,
        duration_ms: 45.0
      )

      html = render_component(InboundRecentPage, %{id: "test"})

      assert html =~ "svc-a"
      assert html =~ "svc-b"
      assert html =~ "GET:/api/items"
      assert html =~ "POST:/api/orders"
      assert html =~ "200"
      assert html =~ "500"
    end

    test "renders with consumer and route filters" do
      insert_inbound_event(method: "GET", path: "/api/items", consumer: "svc-a")
      insert_inbound_event(method: "POST", path: "/api/orders", consumer: "svc-b")

      html =
        render_component(InboundRecentPage, %{
          id: "test",
          consumer: "svc-a",
          route: "GET:/api/items"
        })

      assert html =~ "svc-a"
      assert html =~ "GET:/api/items"
      refute html =~ "data-label=\"Consumer\">svc-b"
    end
  end

  describe "handle_event/3" do
    test "filter_status_class sends navigation" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_status_class: "",
          filter_consumer: "",
          filter_route: ""
        }
      }

      assert {:noreply, _socket} =
               InboundRecentPage.handle_event(
                 "filter_status_class",
                 %{"status_class" => "4xx"},
                 socket
               )

      assert_received {:navigate, url}
      assert url =~ "status_class=4xx"
    end

    test "filter_consumer sends navigation" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_status_class: "",
          filter_consumer: "",
          filter_route: ""
        }
      }

      assert {:noreply, _socket} =
               InboundRecentPage.handle_event("filter_consumer", %{"consumer" => "myapp"}, socket)

      assert_received {:navigate, url}
      assert url =~ "consumer=myapp"
    end

    test "filter_route sends navigation" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_status_class: "",
          filter_consumer: "",
          filter_route: ""
        }
      }

      assert {:noreply, _socket} =
               InboundRecentPage.handle_event("filter_route", %{"route" => "GET:/api"}, socket)

      assert_received {:navigate, url}
      assert url =~ "route=GET:/api"
    end

    test "go_page sends navigation with page number" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_status_class: "",
          filter_consumer: "",
          filter_route: ""
        }
      }

      assert {:noreply, _socket} =
               InboundRecentPage.handle_event("go_page", %{"page" => "3"}, socket)

      assert_received {:navigate, url}
      assert url =~ "page=3"
    end
  end
end
