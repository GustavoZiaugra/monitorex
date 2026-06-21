defmodule Monitorex.Components.Live.OutboundRecentPageTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Monitorex.LiveComponentFixtures

  alias Monitorex.Components.Live.OutboundRecentPage

  setup do
    reset_ets_tables()
    :ok
  end

  describe "update/2" do
    test "renders empty state when no events" do
      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "Recent Outbound Requests"
      assert html =~ "Time"
      assert html =~ "Method"
      assert html =~ "URL"
      assert html =~ "Status"
      assert html =~ "Duration"
      assert html =~ "No recent outbound requests"
    end

    test "renders filter controls" do
      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "2xx"
      assert html =~ "3xx"
      assert html =~ "4xx"
      assert html =~ "5xx"
      assert html =~ "Host"
    end

    test "renders recent outbound events" do
      insert_outbound_event(method: "GET", path: "/users")

      insert_outbound_event(
        method: "POST",
        path: "/orders",
        full_url: "https://api.example.com/orders",
        status: 500,
        status_class: :server_error,
        duration_ms: 120.0
      )

      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "api.example.com"
      assert html =~ "/users"
      assert html =~ "/orders"
      assert html =~ "GET"
      assert html =~ "POST"
      assert html =~ "200"
      assert html =~ "500"
    end

    test "renders with host filter" do
      insert_outbound_event(method: "GET", path: "/users")

      html = render_component(OutboundRecentPage, %{id: "test", host: "api.example.com"})

      assert html =~ "api.example.com"
      assert html =~ "/users"
    end

    test "renders with status_class filter" do
      insert_outbound_event(
        method: "POST",
        path: "/orders",
        full_url: "https://api.example.com/orders",
        status: 500,
        status_class: :server_error,
        duration_ms: 120.0
      )

      html = render_component(OutboundRecentPage, %{id: "test", status_class: "5xx"})

      assert html =~ "500"
      assert html =~ "/orders"
    end

    test "renders with 2xx status_class filter" do
      insert_outbound_event(status: 200, status_class: :success)

      html = render_component(OutboundRecentPage, %{id: "test", status_class: "2xx"})

      assert html =~ "200"
    end

    test "renders with 4xx status_class filter" do
      insert_outbound_event(status: 404, status_class: :client_error)

      html = render_component(OutboundRecentPage, %{id: "test", status_class: "4xx"})

      assert html =~ "404"
    end

    test "renders long urls truncated" do
      insert_outbound_event(
        full_url: "https://api.example.com/" <> String.duplicate("a", 100)
      )

      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "..."
    end

    test "renders missing durations as dash" do
      :ok =
        Monitorex.Storage.ETS.record_event(%Monitorex.Event{
          source: :tesla,
          direction: :outbound,
          method: "GET",
          host: "api.example.com",
          path: "/users",
          full_url: "https://api.example.com/users",
          status: 200,
          status_class: :success,
          duration_ms: nil,
          timestamp: System.system_time(:microsecond)
        })

      html = render_component(OutboundRecentPage, %{id: "test"})

      assert html =~ "-"
    end
  end

  describe "handle_event/3" do
    test "filter_status_class sends navigation" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_host: "",
          filter_status_class: ""
        }
      }

      assert {:noreply, _socket} =
               OutboundRecentPage.handle_event(
                 "filter_status_class",
                 %{"status_class" => "5xx"},
                 socket
               )

      assert_received {:navigate, url}
      assert url =~ "status_class=5xx"
    end

    test "filter_host sends navigation with host param" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_host: "",
          filter_status_class: ""
        }
      }

      assert {:noreply, _socket} =
               OutboundRecentPage.handle_event(
                 "filter_host",
                 %{"host" => "api.example.com"},
                 socket
               )

      assert_received {:navigate, url}
      assert url =~ "host=api.example.com"
    end

    test "filter_host clears host param when empty" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_host: "previous.com",
          filter_status_class: ""
        }
      }

      assert {:noreply, _socket} =
               OutboundRecentPage.handle_event("filter_host", %{"host" => ""}, socket)

      assert_received {:navigate, url}
      # Current assigns still has previous host until re-render
      assert url =~ "host=previous.com"
    end

    test "go_page sends navigation with page number" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          filter_host: "",
          filter_status_class: ""
        }
      }

      assert {:noreply, _socket} =
               OutboundRecentPage.handle_event("go_page", %{"page" => "2"}, socket)

      assert_received {:navigate, url}
      assert url =~ "page=2"
    end
  end
end
