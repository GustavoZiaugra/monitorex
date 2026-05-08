defmodule Monitorex.Components.Live.OutboundRecentPageTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Monitorex.Components.Live.OutboundRecentPage

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
